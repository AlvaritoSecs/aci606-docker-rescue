# ACI606 - Docker Rescue Challenge (solución reparada)

Aplicación multi-servicio: **Frontend (Nginx) -> Backend/API (FastAPI) -> Database (PostgreSQL)**, ejecutada con Docker Compose.

## Arquitectura final

Diagramas: [arquitectura inicial](docs/arquitectura_inicial.svg) · [arquitectura final](docs/arquitectura_final.svg) · informe técnico en [`docs/`](docs/).

```
Navegador --(host:8080)--> frontend (nginx:80) --/api/--> backend (uvicorn:8000) --> db (postgres:5432)
                                                                                     |
                                                                          volumen pgdata (datos)
```

- Red interna: `rescue_net`. Los servicios se comunican por **nombre de servicio** (`backend`, `db`), nunca por `localhost`.
- Solo el frontend publica un puerto al host (`FRONTEND_PORT`, por defecto 8080). Backend y base de datos quedan internos.
- Persistencia: volumen nombrado `pgdata` montado en `/var/lib/postgresql/data`.
- Healthchecks: `db` (pg_isready), `backend` (GET /health, que también prueba la base), `frontend` (GET /).
- Orden de arranque: `db` sano -> `backend` sano -> `frontend`.
- El backend se ejecuta con un usuario sin privilegios (`appuser`); cada servicio tiene su `.dockerignore`.

## Estructura

```
compose.yaml            servicios, red, volumen y healthchecks
.env.example            variables configurables (copiar a .env)
.devcontainer/          entorno de GitHub Codespaces (Docker + creación de .env)
backend/                FastAPI: Dockerfile, requirements.txt, main.py
frontend/               Nginx: Dockerfile, nginx.conf, index.html
docs/                   diagramas de arquitectura e informe técnico
evidencias/             salidas reales de diagnóstico, reparaciones y pruebas
scripts/                recolectar_evidencias.sh (reproduce toda la evidencia)
```

## Configuración

Las variables están en `.env.example`. Docker Compose lee automáticamente un archivo `.env` si existe; si no existe, usa los valores por defecto definidos en `compose.yaml`.

```bash
cp .env.example .env   # opcional: para cambiar usuario, contraseña, base o puerto
```

| Variable | Uso | Por defecto |
|---|---|---|
| POSTGRES_USER | usuario de PostgreSQL (db y backend) | appuser |
| POSTGRES_PASSWORD | contraseña de PostgreSQL (db y backend) | rescue123 |
| POSTGRES_DB | nombre de la base | appdb |
| FRONTEND_PORT | puerto del host para el frontend | 8080 |

`DATABASE_URL` del backend se arma con las mismas variables, así la base y la API no pueden quedar con credenciales distintas.

## Iniciar en GitHub Codespaces

1. En el repositorio: **Code > Codespaces > Create codespace on main**.
2. Al crearse, el Codespace copia `.env.example` a `.env` automáticamente (`.devcontainer/devcontainer.json`).
3. En la terminal:

```bash
docker compose up --build -d
docker compose ps        # los 3 servicios deben quedar "healthy" (~30 s)
```

4. Pestaña **Ports** → puerto **8080** → abrir en el navegador.

## Iniciar (cualquier equipo con Docker)

```bash
docker compose up --build -d
docker compose ps        # esperar a que los 3 servicios aparezcan "healthy"
```

## Verificar

```bash
curl -s http://localhost:8080/api/health
curl -s -X POST http://localhost:8080/api/items -H "Content-Type: application/json" -d '{"name":"prueba"}'
curl -s http://localhost:8080/api/items
docker compose exec db psql -U appuser -d appdb -c "SELECT * FROM items;"
```

En Codespaces, abrir la pestaña **Ports** y el puerto **8080** para ver la interfaz web.

## Observar y diagnosticar

```bash
docker compose ps
docker compose logs <servicio>
docker inspect <contenedor>
docker volume ls
docker network ls
```

## Detener

```bash
docker compose down        # elimina contenedores y red; los datos quedan en el volumen pgdata
```

## Recrear

```bash
docker compose up --build -d   # los registros creados antes siguen disponibles
```

Para borrar también los datos (reinicio total): `docker compose down -v`.

## Reparaciones

| ID | Falla | Corrección | Commit |
|---|---|---|---|
| R-01 | `CMD` del backend ejecutaba `app:app` (módulo inexistente) | `main:app` | `R-01: ...` |
| R-02 | Faltaba el driver de PostgreSQL | `psycopg2-binary==2.9.10` | `R-02: ...` |
| R-03 | `DATABASE_URL` apuntaba a `localhost` | host `db` | `R-03: ...` |
| R-04 | Contraseña distinta entre backend y base | misma credencial (luego desde `.env`) | `R-04: ...` |
| R-05 | Puerto `8080:8080`, nginx escucha en 80 | `8080:80` | `R-05: ...` |
| R-06 | `proxy_pass` de nginx a `localhost:8000` | `http://backend:8000/` | `R-06: ...` |
| R-07 | Backend se conectaba antes de que PostgreSQL estuviera listo | healthcheck `pg_isready` + `service_healthy` | `R-07: ...` |
| R-08 | Sin volumen nombrado: datos perdidos al recrear | volumen `pgdata` | `R-08: ...` |

El detalle (síntoma, evidencia, causa raíz, justificación, verificación e impacto) está en el informe técnico.

## Evidencias reproducibles

`scripts/recolectar_evidencias.sh` vuelve al commit anterior a cada reparación, reproduce el síntoma, aplica el commit de la reparación y registra la verificación; luego ejecuta las pruebas de validación sobre la versión final. Las salidas quedan en `evidencias/`.

```bash
bash scripts/recolectar_evidencias.sh   # requiere árbol de trabajo limpio (~6 min)
```

El workflow `.github/workflows/evidencias.yml` ejecuta el mismo script en una máquina limpia de GitHub Actions.
