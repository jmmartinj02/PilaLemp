#!/bin/bash

## CONFIGURACIÓN ##
LOG_GLOBAL="/var/log/gestor_archivos.log"
LOG_USUARIO="$HOME/gestor_archivos_user.log"
#uso el temp para almacenar datos que utilziaré en las operaciones
#en un principio lo utilicé como depurador en el desarrollo
#pero he visto que podia darle utilidad.
TEMP_RESULTS="/tmp/gestor_archivos.tmp"

## FUNCIONES BÁSICAS ##

#creacion de logs
iniciar_logs() {
    # Log global (root)
    if [ "$(id -u)" -eq 0 ] && [ ! -f "$LOG_GLOBAL" ]; then
        touch "$LOG_GLOBAL"
        chmod 600 "$LOG_GLOBAL"
        echo "Iniciado log global en $LOG_GLOBAL" >> "$LOG_GLOBAL"
    fi
    
    #log usuario, si por algun casual el primero en iniciar es el usuario
    #se crea tambien el log global, para que luego, como el usuario
    #hará cambios tambien se registre en el global
    if [ ! -f "$LOG_USUARIO" ] && [ ! -f "$LOG_GLOBAL" ]; then
	touch "$LOG_GLOBAL"
        chmod 600 "$LOG_GLOBAL"
        echo "Iniciado log global en $LOG_GLOBAL" >> "$LOG_GLOBAL"
        touch "$LOG_USUARIO"
        chmod 600 "$LOG_USUARIO"
        echo "Iniciado log de usuario en $LOG_USUARIO" >> "$LOG_USUARIO"
    fi
}

#funcion de registro de acciones
registrar_accion() {
    local mensaje="[$(date '+%Y-%m-%d %H:%M:%S')] Usuario: $(whoami) - $1"
    
    # Todos registran en su log
    echo "$mensaje" >> "$LOG_USUARIO"
    
    # Intento registrar en log global
    if [ "$(id -u)" -eq 0 ]; then
        echo "$mensaje" >> "$LOG_GLOBAL"
    else
    #fuerza el uso del comando aun cuando es usuario, para actualizar el log
        sudo bash -c "echo '$mensaje' >> '$LOG_GLOBAL'" || true
    fi
}

#a partir de aqui las funciones que permiten hacer las busquedas

#funcion que busca por criterios
buscar_archivos() {
    #este es digamos, el formulario de criterios
    local criterios=$(zenity --forms --title="Búsqueda Avanzada" \
        --text="Ingrese los criterios de búsqueda:" \
        --add-entry="Nombre (patrón):" \
        --add-combo="Tamaño:" --combo-values="|+1M|-1M|+10M|+100M" \
        --add-combo="Tipo:" --combo-values="|Archivo|Directorio|Enlace" \
        --add-entry="Permisos (ej: 644):" \
        --add-entry="Usuario propietario:" \
        --add-entry="Grupo propietario:")
    
    [ -z "$criterios" ] && return 1

    # Parsear criterios
    local nombre tamano tipo permisos usuario grupo
    IFS='|' read -r nombre tamano tipo permisos usuario grupo <<< "$criterios"

    #3 dias apra montar este comando.
	#asignado a variable local comando que contiene find /
    local comando="find /"
    # si hay contenido en la variable nombre del ifs, hace un append con -name y el nombre
    [ -n "$nombre" ] && comando+=" -name \"$nombre\""
	#estos 3, solo seleccionas uno, entonces, si el contenido es igual a uno
	#de los tres, en funcion de cual sea,pues le hara el append de uno o otro
    [ "$tipo" = "Archivo" ] && comando+=" -type f"
    [ "$tipo" = "Directorio" ] && comando+=" -type d"
    [ "$tipo" = "Enlace" ] && comando+=" -type l"
	# los demás igual que el de nombre, si contienen algo esas variables
	#hará el append o no
    [ -n "$tamano" ] && comando+=" -size $tamano"
    [ -n "$permisos" ] && comando+=" -perm $permisos"
    [ -n "$usuario" ] && comando+=" -user $usuario"
    [ -n "$grupo" ] && comando+=" -group $grupo"
    
    #el eval, que me da la vida, te quitas de algo de sintaxis
   #lo que ahce es permitir EJECUTAR COMANDOS QUE SE ENCUENTRAN DENTRO DE VARIABLES
   #LO EJECUTA Y LO DEJA EN TEMP_RESULTS
    eval "$comando" > "$TEMP_RESULTS"
    #si existe, que haga el input de la informacion que tenemos en temp result
   #con el mensaje personalizado
    if [ -s "$TEMP_RESULTS" ]; then
        registrar_accion "Búsqueda realizada: $(wc -l < "$TEMP_RESULTS") resultados"
        return 0
    else
   #si al hacer la busqueda no hay nada en TEMP entrará aqui y dirá el zenity que no hemos encontrado nada
        zenity --info --title="Resultados" --text="No se encontraron archivos"
        return 1
    fi
}

#cambio de permisos
cambiar_permisos() {
    local archivos="$1"
    local formato=$(zenity --list --title="Formato de Permisos" \
        --column="ID" --column="Formato" \
        "1" "Octal (ej: 755)" \
        "2" "Simbólico (ej: u+rwx)")
    
    local permisos=""
    case "$formato" in
        "1") 
            permisos=$(zenity --entry --title="Permisos Octal" \
                     --text="Ingrese permisos (3-4 dígitos):" --entry-text="644")
            [[ ! "$permisos" =~ ^[0-7]{3,4}$ ]] && return
            ;;
        "2")
            permisos=$(zenity --entry --title="Permisos Simbólico" \
                     --text="Ingrese permisos (ej: u+rwx):" --entry-text="u+rw")
            ;;
        *) return ;;
    esac
    [ -z "$permisos" ] && return

    # Procesar archivos
    local exitos=0
    while IFS= read -r archivo; do
        if chmod "$permisos" "$archivo" 2>/dev/null; then
            ((exitos++))
            registrar_accion "Cambió permisos de $archivo a $permisos"
        fi
    done <<< "$archivos"
    
    zenity --info --title="Resultado" --text="Permisos cambiados en $exitos archivos"
}

# Cambiar propietario
cambiar_propietario() {
#archivos recibe la lista de archivos a modificar
    local archivos="$1"
#variable nuevo propietario... blah blah blah
    local nuevo_prop=$(zenity --entry --title="Nuevo Propietario" \
        --text="Ingrese usuario:grupo nuevo:")
    [ -z "$nuevo_prop" ] && return
#variable exitos, inicializada a 0, la usaré luego
#itera sobre todos los archivos, aquellos que si pilla, aumenta contador en 1
    local exitos=0
    while IFS= read -r archivo; do
        if sudo chown "$nuevo_prop" "$archivo"; then
            ((exitos++))
            registrar_accion "Cambió propietario de $archivo a $nuevo_prop"
        fi
    done <<< "$archivos"
    
    zenity --info --title="Resultado" --text="Propietario cambiado en $exitos archivos"
}

# Eliminar archivos
eliminar_archivos() {
# de nuevo la lista de archivos
    local archivos="$1"
    #caballero, esta usted seguro de que sea borrarlos? si no, pa fuera
    zenity --question --title="Confirmar" --text="¿Eliminar los archivos seleccionados?" --width=300
    [ "$?" -ne 0 ] && return
# si has dicho que si, te preguntará si quieres hacer un backup, es otra funcion
#la explicaré luego
    zenity --question --title="Backup" --text="¿Crear copia de seguridad?"
    if [ "$?" -eq 0 ]; then
        crear_backup "$archivos"
    fi

    #he hecho otro contador, iteramos el contenido de archivo y vamos borrando
    # por cada uno que se haga, aumenta el contador, para luego mostrar la cantidad que hemos borrado
    local exitos=0
    while IFS= read -r archivo; do
        if rm -rf "$archivo"; then
            ((exitos++))
            registrar_accion "Eliminó archivo: $archivo"
        fi
    done <<< "$archivos"
    
    zenity --info --title="Resultado" --text="Se eliminaron $exitos archivos"
}

#aqui está la funcion backup
crear_backup() {
    local archivos="$1"
#funciona por ruta absoluta, esta funcion es de administrador, no deberia de haber problema de permisos
    local destino=$(zenity --file-selection --directory --title="Seleccione destino para backup")
    [ -z "$destino" ] && return

    local dir_backup="$destino/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$dir_backup"
#de nuevo itera con archivo... blah blah, pero esta vez para que en cada vuelta meta el archivo en el directorio backup
    while IFS= read -r archivo; do
        local dir_archivo=$(dirname "$archivo")
        mkdir -p "$dir_backup$dir_archivo"
        cp -a "$archivo" "$dir_backup$dir_archivo/"
    done <<< "$archivos"
    
    zenity --info --title="Backup" --text="Copia creada en:\n$dir_backup"
}

menu_principal() {
    while true; do
        local opcion=$(zenity --list --title="Gestor de Archivos" \
            --text="Seleccione una operación:" \
            --column="ID" --column="Opción" \
            "1" "Buscar archivos" \
            "2" "Cambiar permisos" \
            "3" "Cambiar propietario" \
            "4" "Ver logs" \
            "5" "Salir" )
        
        case "$opcion" in
            "1")
                if buscar_archivos; then
                    local archivos=$(cat "$TEMP_RESULTS")
                    local accion=$(zenity --list --title="Acciones" \
                        --text="Seleccione acción:" \
                        --column="ID" --column="Acción" \
                        "1" "Cambiar permisos" \
                        "2" "Cambiar propietario" \
                        "3" "Eliminar archivos")
                    
                    case "$accion" in
                        "1") cambiar_permisos "$archivos" ;;
                        "2") cambiar_propietario "$archivos" ;;
                        "3") eliminar_archivos "$archivos" ;;
                    esac
                fi
                ;;
            "2")
                local archivos=$(zenity --file-selection --multiple --separator=$'\n')
                [ -n "$archivos" ] && cambiar_permisos "$archivos"
                ;;
            "3")
                local archivos=$(zenity --file-selection --multiple --separator=$'\n')
                [ -n "$archivos" ] && cambiar_propietario "$archivos"
                ;;
            "4") ver_logs ;;
            "5") break ;;
        esac
    done
}

#para ver los logs, como puedes verlo de dos maneras diferentes
#una, como root, entonces, si el id es root, entonces mete dentro de la variable log_file
#el log global y luego con una tuberia mete el log usuario, con lo cual en log_file estan ambos
#si fuese usuario, entonces solo el log usuario
ver_logs() {
    local log_file="$([ "$(id -u)" -eq 0 ] && echo "$LOG_GLOBAL" || echo "$LOG_USUARIO")"
    
    local opcion=$(zenity --list --title="Visualizar Logs" \
        --text="Seleccione opción:" \
        --column="ID" --column="Opción" \
        "1" "Últimas entradas" \
        "2" "Buscar por usuario" \
#muy facil, exportarlos es crear otro archivo con todo el contenido de log_file, para verlo de forma mas detallada, o por si por algun casual, lo necesitas, porque el pequeño timmy le ha gastado una broma pesada al pequeño jimmy cambiandole los permisos a sus archivos
        "3" "Exportar logs")
    
    case "$opcion" in
        "1")
#las ultimas entradas, pues 20 de ellas
            zenity --text-info --title="Últimas entradas" --filename=<(tail -20 "$log_file") \
                   --width=800 --height=600
            ;;
        "2")
#si quieres, puedes buscar especificamente por usuario haciendo un simple grep
            local usuario=$(zenity --entry --title="Buscar" --text="Ingrese usuario:")
            [ -n "$usuario" ] && zenity --text-info --title="Resultados" \
                                        --filename=<(grep "Usuario: $usuario" "$log_file") \
                                        --width=800 --height=600
            ;;
        "3")
            local destino=$(zenity --file-selection --save --title="Guardar logs" \
                                 --filename="logs_$(date +%Y%m%d).txt")
            [ -n "$destino" ] && cp "$log_file" "$destino" && \
                zenity --info --text="Logs exportados a $destino"
            ;;
    esac
}

#lo mas facil del programa, dos tonterias, llamar a las funciones como un arbol
iniciar_logs

if [ "$(id -u)" -eq 0 ]; then
    menu_principal
else
    zenity --info --title="Información" \
           --text="Algunas funciones requieren permisos de administrador" \
           --width=300
    menu_principal
fi

#limpieza de los archivos temporales, con el que jugamos con los datos que obtenemos con los find y otros comandos.
rm -f "$TEMP_RESULTS"
