# ACI606 - Docker Rescue Challenge (solución reparada)

Aplicación multi-servicio: **Frontend (Nginx) -> Backend/API (FastAPI) -> Database (PostgreSQL)**, ejecutada con Docker Compose.

## Arquitectura final

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

## Iniciar

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

El detalle de cada incidencia (R-01, R-02, ...) está en el informe técnico y en el historial de commits. La carpeta `evidencias/` contiene las salidas de los comandos usados para diagnosticar y verificar.
