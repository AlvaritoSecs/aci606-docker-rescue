#!/usr/bin/env bash
# Recolecta evidencia reproducible de cada incidencia y de las pruebas obligatorias.
#
# Para cada reparacion R-XX:
#   1) se vuelve al commit ANTERIOR a la reparacion y se registra el sintoma (estado, logs, curl);
#   2) se pasa al commit de la reparacion y se registra la verificacion.
# Al final se ejecutan las pruebas P1-P6 sobre la version final (rama actual).
#
# Uso (desde la raiz del repositorio, con el arbol de trabajo limpio):
#   bash scripts/recolectar_evidencias.sh
# Resultado: carpeta evidencias/ con un .txt por incidencia/prueba (comando + salida real).
set -u

# git checkout cambia los archivos del repo (incluido este script): se ejecuta una copia en /tmp.
if [ -z "${_EV_COPIA:-}" ]; then
  cp "$0" /tmp/recolectar_evidencias.sh
  _EV_COPIA=1 exec bash /tmp/recolectar_evidencias.sh "$@"
fi

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"
RAMA="$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)"
if [ -n "$(git status --porcelain)" ]; then
  echo "El arbol de trabajo tiene cambios sin commit. Haz commit o stash antes de ejecutar." >&2
  exit 1
fi

EV=/tmp/evidencias
rm -rf "$EV"; mkdir -p "$EV"
BUILD_LOG="$EV/_build.log"

# ev ID "comando": guarda el comando y su salida real en evidencias/ID.txt
ev() {
  local f="$EV/$1.txt"
  { echo "\$ $2"; bash -c "$2" 2>&1; echo; } >> "$f"
  echo "   [$1] $2"
}
nota() { echo "## $2" >> "$EV/$1.txt"; }
paso() { echo; echo "=== $1"; }
# Commit de cada etapa, buscado por el asunto del commit (inicial, r01..r08, mejoras).
ref_de() {
  local p
  case "$1" in
    inicial) p='^Estado inicial' ;;
    mejoras) p='^Mejoras:' ;;
    r0[1-9]) p="^R-0${1#r0}:" ;;
    *) echo "$1"; return ;;
  esac
  git log --format=%H -n1 -E --grep="$p" "$RAMA"
}
ir() {
  git checkout -q "$(ref_de "$1")"
  echo "   (codigo en '$1': $(git log -1 --format=%s))"
  for id in "${@:2}"; do echo "## Codigo en $1 ($(git rev-parse --short HEAD)): $(git log -1 --format=%s)" >> "$EV/$id.txt"; done
}
subir() { docker compose up --build -d >> "$BUILD_LOG" 2>&1; sleep "${1:-8}"; }
bajar() { docker compose down "$@" --remove-orphans >> "$BUILD_LOG" 2>&1; }
esperar_sano() {
  for _ in $(seq 1 40); do
    [ "$(docker compose ps | grep -c '(healthy)')" -ge "${1:-3}" ] && return 0
    sleep 3
  done
  echo "   (aviso: no se alcanzaron ${1:-3} servicios healthy)"
}
captura() {
  local chrome
  chrome="$(command -v google-chrome || command -v chromium || command -v chromium-browser || true)"
  [ -z "$chrome" ] && return 0
  "$chrome" --headless=new --no-sandbox --disable-gpu --hide-scrollbars --window-size=900,650 \
    --virtual-time-budget=8000 --screenshot="$EV/$1.png" http://localhost:8080/ >/dev/null 2>&1 || true
  echo "   [captura] $1.png"
}
POST_ITEM() { echo "curl -s -X POST localhost:8080/api/items -H 'Content-Type: application/json' -d '{\"name\":\"$1\"}'"; }

docker version --format 'Docker {{.Server.Version}}' > "$EV/_entorno.txt" 2>&1
docker compose version >> "$EV/_entorno.txt" 2>&1
date -u +"Fecha (UTC): %Y-%m-%d %H:%M:%S" >> "$EV/_entorno.txt"

# ---------------------------------------------------------------- incidencias
paso "Estado inicial"
ir inicial R-01
bajar -v
subir 10
nota R-01 "SINTOMA"
ev R-01 "docker compose ps -a"
ev R-01 "docker compose logs --tail 20 backend"

paso "R-01 -> verificacion / R-02 sintoma"
ir r01 R-01 R-02
subir 10
nota R-01 "VERIFICACION (el error de importacion de 'app' desaparece)"
ev R-01 "docker compose logs --tail 20 backend"
nota R-02 "SINTOMA"
ev R-02 "docker compose ps -a"
ev R-02 "docker compose logs --tail 20 backend"

paso "R-02 -> verificacion / R-03 sintoma"
ir r02 R-02 R-03
subir 10
nota R-02 "VERIFICACION (el modulo psycopg2 ya se importa)"
ev R-02 "docker compose exec -T backend pip show psycopg2-binary || docker compose run --rm --no-deps -T backend pip show psycopg2-binary"
nota R-03 "SINTOMA"
ev R-03 "docker compose ps -a"
ev R-03 "docker compose logs --tail 20 backend"
ev R-03 "docker compose config | grep DATABASE_URL"
ev R-03 "docker compose run --rm --no-deps -T --entrypoint sh backend -c 'echo localhost:; getent hosts localhost; echo db:; getent hosts db'"

paso "R-03 -> verificacion / R-04 sintoma"
ir r03 R-03 R-04
subir 10
nota R-03 "VERIFICACION (el backend ya llega al servicio db)"
ev R-03 "docker compose logs --tail 20 backend"
nota R-04 "SINTOMA"
ev R-04 "docker compose ps -a"
ev R-04 "docker compose logs --tail 20 backend"
ev R-04 "docker compose logs --tail 10 db"

paso "R-04 -> verificacion / R-05 sintoma"
ir r04 R-04 R-05
subir 10
nota R-04 "VERIFICACION"
ev R-04 "docker compose ps -a"
ev R-04 "docker compose exec -T backend python -c \"import urllib.request;print(urllib.request.urlopen('http://localhost:8000/health').read().decode())\""
nota R-05 "SINTOMA"
ev R-05 "curl -sv --max-time 5 http://localhost:8080/"
ev R-05 "docker compose ps"
ev R-05 "docker compose exec -T frontend grep -n listen /etc/nginx/conf.d/default.conf"

paso "R-05 -> verificacion / R-06 sintoma"
ir r05 R-05 R-06
subir 8
nota R-05 "VERIFICACION"
ev R-05 "docker compose ps"
ev R-05 "curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8080/"
nota R-06 "SINTOMA"
ev R-06 "curl -s -i --max-time 5 http://localhost:8080/api/health"
ev R-06 "docker compose logs --tail 6 frontend"
captura R-06_navegador_sintoma

paso "R-06 -> verificacion"
ir r06 R-06
subir 8
nota R-06 "VERIFICACION"
ev R-06 "curl -s -i http://localhost:8080/api/health"
ev R-06 "$(POST_ITEM primer-registro)"
ev R-06 "curl -s http://localhost:8080/api/items"
captura R-06_navegador_reparado

paso "R-07 sintoma: arranque limpio (sin datos previos)"
bajar -v
subir 4
nota R-07 "SINTOMA (arranque limpio con 'docker compose down -v' + 'up'; codigo en r06)"
ev R-07 "docker compose ps -a"
ev R-07 "docker compose logs --tail 20 backend"
ev R-07 "docker compose logs --tail 8 db"

paso "R-07 -> verificacion / R-08 sintoma"
bajar -v
ir r07 R-07 R-08
subir 4
esperar_sano 1
sleep 5
nota R-07 "VERIFICACION (arranque limpio: backend espera a db healthy)"
ev R-07 "docker compose ps -a"
ev R-07 "docker compose logs --tail 8 backend"
nota R-08 "SINTOMA: se crea un registro, se recrean los contenedores y se consulta"
ev R-08 "$(POST_ITEM antes-de-recrear)"
ev R-08 "curl -s http://localhost:8080/api/items"
ev R-08 "docker compose down"
subir 4; esperar_sano 1; sleep 5
ev R-08 "curl -s http://localhost:8080/api/items"
ev R-08 "docker volume ls"

paso "R-08 -> verificacion"
bajar -v
ir r08 R-08
subir 4; esperar_sano 1; sleep 5
nota R-08 "VERIFICACION (volumen nombrado pgdata)"
ev R-08 "$(POST_ITEM persistente)"
ev R-08 "docker compose down"
subir 4; esperar_sano 1; sleep 5
ev R-08 "curl -s http://localhost:8080/api/items"
ev R-08 "docker volume ls"

paso "Mejoras"
bajar -v
ir mejoras MEJORAS
subir 5; esperar_sano 3
ev MEJORAS "docker compose ps"
ev MEJORAS "docker network ls"
ev MEJORAS "docker volume ls"
ev MEJORAS "docker inspect --format '{{.Name}} -> {{json .State.Health.Status}}' \$(docker compose ps -q)"
ev MEJORAS "docker network inspect aci606-docker-rescue_rescue_net --format '{{range .Containers}}{{.Name}}  {{.IPv4Address}}{{println}}{{end}}'"
bajar -v

# ---------------------------------------------------------------- pruebas P1-P6 (version final)
paso "Pruebas obligatorias sobre la version final ($RAMA)"
ir "$RAMA" P1
nota P1 "PREPARACION: .env a partir de .env.example (en Codespaces lo hace postCreateCommand)"
ev P1 "test -f .env && echo '.env ya existe' || cp -v .env.example .env"
nota P1 "ARRANQUE LIMPIO desde el proyecto detenido"
ev P1 "docker compose ps -a"
ev P1 "docker compose --progress plain up --build -d 2>&1 | tail -12"
esperar_sano 3
ev P1 "docker compose ps"
ev P1 "docker compose exec -T backend id"

nota P2 "COMUNICACION frontend -> backend -> PostgreSQL"
ev P2 "curl -s http://localhost:8080/api/health"
ev P2 "$(POST_ITEM robot-1)"
ev P2 "$(POST_ITEM robot-2)"
ev P2 "curl -s http://localhost:8080/api/items"
ev P2 "docker compose exec -T db psql -U appuser -d appdb -c 'SELECT id, name, created_at FROM items;'"
captura P2_navegador

nota P3 "PERSISTENCIA: se recrean todos los contenedores (down + up) y se consulta"
ev P3 "docker compose down"
ev P3 "docker compose ps -a"
ev P3 "docker compose up -d 2>&1 | tail -5"
esperar_sano 3
ev P3 "curl -s http://localhost:8080/api/items"
ev P3 "docker volume inspect \$(docker volume ls -q | grep pgdata)"

nota P4 "FALLO CONTROLADO: se detiene el servicio db"
ev P4 "docker compose stop db"
sleep 10
ev P4 "curl -s -i http://localhost:8080/api/health"
ev P4 "curl -s -o /dev/null -w 'Frontend (pagina) HTTP %{http_code}\n' http://localhost:8080/"
captura P4_navegador_fallo

nota P5 "DIAGNOSTICO del fallo"
sleep 45
ev P5 "docker compose ps -a"
ev P5 "docker compose logs --tail 12 backend"
ev P5 "docker inspect --format '{{json .State.Health}}' \$(docker compose ps -q backend)"

nota P6 "RECUPERACION: se vuelve a iniciar db"
ev P6 "docker compose start db"
esperar_sano 3
ev P6 "docker compose ps"
ev P6 "curl -s http://localhost:8080/api/health"
ev P6 "curl -s http://localhost:8080/api/items"
captura P6_navegador_recuperado

nota P4b "FALLO CONTROLADO 2: se detiene el servicio backend"
ev P4b "docker compose stop backend"
ev P4b "curl -s -i --max-time 15 http://localhost:8080/api/health"
ev P4b "docker compose logs --tail 3 frontend"
ev P4b "docker compose ps -a"
captura P4b_navegador_backend_detenido
nota P4b "RECUPERACION"
ev P4b "docker compose start backend"
esperar_sano 3
ev P4b "docker compose ps"
ev P4b "curl -s http://localhost:8080/api/items"

nota P7 "CONFIGURACION EXTERNALIZADA: cambiar el puerto publicado solo editando .env (sin tocar compose.yaml ni reconstruir)"
cp .env /tmp/env.respaldo
ev P7 "sed -i 's/^FRONTEND_PORT=.*/FRONTEND_PORT=9090/' .env && grep FRONTEND_PORT .env"
ev P7 "docker compose up -d 2>&1 | tail -4"
esperar_sano 3
ev P7 "docker compose ps frontend"
ev P7 "curl -s -o /dev/null -w 'puerto 9090 -> HTTP %{http_code}\n' http://localhost:9090/"
ev P7 "curl -s -o /dev/null --max-time 3 -w 'puerto 8080 -> HTTP %{http_code}\n' http://localhost:8080/ || true"
cp /tmp/env.respaldo .env
ev P7 "docker compose up -d 2>&1 | tail -4"
esperar_sano 3
ev P7 "docker compose ps frontend"

bajar
rm -rf "$REPO/evidencias"; cp -r "$EV" "$REPO/evidencias"
echo; echo "Listo. Evidencias en: $REPO/evidencias"; ls "$REPO/evidencias"
