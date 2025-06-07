#!/bin/bash

# Configuración de logs
LOG_GLOBAL="/var/log/gestor_archivos.log"
LOG_USUARIO="$HOME/gestor_archivos_user.log"
TEMP_RESULTS="/tmp/gestor_archivos.tmp"

# Función para crear logs
crear_logs() {
    if [[ $EUID -eq 0 ]]; then
        [ ! -f "$LOG_GLOBAL" ] && { touch "$LOG_GLOBAL"; chmod 600 "$LOG_GLOBAL"; }
    else
        [ ! -f "$LOG_USUARIO" ] && { touch "$LOG_USUARIO"; chmod 600 "$LOG_USUARIO"; }
    fi
}

# Función de registro de acciones
registrar_log() {
    local mensaje="[$(date '+%Y-%m-%d %H:%M:%S')] Usuario: $(whoami) - $1"
    
    if [[ $EUID -eq 0 ]]; then
        echo "$mensaje" >> "$LOG_GLOBAL"
    else
        echo "$mensaje" >> "$LOG_USUARIO"
        echo "$mensaje" | sudo tee -a "$LOG_GLOBAL" >/dev/null 2>&1 || true
    fi
}

# Función para seleccionar múltiples archivos
seleccionar_archivos() {
    zenity --file-selection --multiple --separator="|" --title="Seleccione archivos" 2>/dev/null
}

# Función para buscar archivos por usuario (solo admin)
buscar_por_usuario() {
    local usuario=$(zenity --entry --title="Buscar archivos por usuario" \
                          --text="Ingrese el nombre de usuario:" 2>/dev/null)
    [ -z "$usuario" ] && return

    # Buscar todos los archivos del usuario
    find / -user "$usuario" -printf '%p|%u|%g|%m\n' 2>/dev/null > "${TEMP_RESULTS}_full"
    
    if [ -s "${TEMP_RESULTS}_full" ]; then
        awk -F'|' '{print $1}' "${TEMP_RESULTS}_full" > "$TEMP_RESULTS"
        
        # Mostrar resumen
        local total_archivos=$(wc -l < "$TEMP_RESULTS")
        zenity --info --title="Resultados" \
               --text="Se encontraron $total_archivos archivos del usuario $usuario" \
               2>/dev/null
        
        # Mostrar menú de acciones masivas
        menu_acciones_masivas "$usuario"
    else
        zenity --info --title="Resultados" \
               --text="No se encontraron archivos del usuario $usuario" \
               2>/dev/null
    fi
}

# Menú de acciones masivas para archivos de usuario
menu_acciones_masivas() {
    local usuario="$1"
    local opcion=$(zenity --list --title="Acciones Masivas" \
        --text="Seleccione acción para los archivos de $usuario:" \
        --column="ID" --column="Acción" \
        "1" "Cambiar propietario" \
        "2" "Eliminar archivos" \
        "3" "Cambiar permisos" \
        "4" "Mover a directorio" \
        2>/dev/null)
    
    case "$opcion" in
        "1")
            cambiar_propietario_masivo "$usuario"
            ;;
        "2")
            eliminar_archivos_masivo "$usuario"
            ;;
        "3")
            cambiar_permisos_masivo "$usuario"
            ;;
        "4")
            mover_archivos_masivo "$usuario"
            ;;
    esac
}

# Función para cambiar propietario masivo
cambiar_propietario_masivo() {
    local usuario_original="$1"
    local nuevo_prop=$(zenity --entry --title="Cambiar Propietario Masivo" \
        --text="Ingrese el nuevo propietario (usuario:grupo) para los archivos de $usuario_original:" \
        2>/dev/null)
    [ -z "$nuevo_prop" ] && return

    # Confirmación importante
    zenity --question --title="Confirmación" \
           --text="¿Está seguro de cambiar el propietario de TODOS los archivos de $usuario_original a $nuevo_prop?\n\nEsta acción no se puede deshacer." \
           --ok-label="Confirmar" --cancel-label="Cancelar" \
           --width=400 2>/dev/null || return

    # Procesar cambio
    local contador=0
    while IFS='|' read -r archivo _ _ _; do
        if sudo chown "$nuevo_prop" "$archivo" 2>/dev/null; then
            ((contador++))
            registrar_log "Cambió propietario de $archivo de $usuario_original a $nuevo_prop"
        fi
    done < "${TEMP_RESULTS}_full"

    zenity --info --title="Resultado" \
           --text="Se cambiaron $contador archivos de $usuario_original a $nuevo_prop" \
           2>/dev/null
}

# Función para eliminar archivos masivamente
eliminar_archivos_masivo() {
    local usuario="$1"
    
    zenity --question --title="Confirmación de Eliminación" \
           --text="¿Está seguro de eliminar TODOS los archivos de $usuario?\n\nEsta acción es irreversible." \
           --ok-label="Eliminar" --cancel-label="Cancelar" \
           --width=400 2>/dev/null || return

    # Opción de backup antes de eliminar
    if zenity --question --title="Crear Backup" \
              --text="¿Desea crear un backup de los archivos antes de eliminarlos?" \
              2>/dev/null; then
        crear_backup "$usuario"
    fi

    # Procesar eliminación
    local contador=0
    while IFS='|' read -r archivo _ _ _; do
        if sudo rm -rf "$archivo" 2>/dev/null; then
            ((contador++))
            registrar_log "Eliminó archivo: $archivo (de $usuario)"
        fi
    done < "${TEMP_RESULTS}_full"

    zenity --info --title="Resultado" \
           --text="Se eliminaron $contador archivos de $usuario" \
           2>/dev/null
}

# Función para crear backup
crear_backup() {
    local usuario="$1"
    local dir_backup=$(zenity --file-selection --directory --title="Seleccione directorio para backup" 2>/dev/null)
    [ -z "$dir_backup" ] && return

    local fecha=$(date +%Y%m%d_%H%M%S)
    local dir_destino="$dir_backup/backup_${usuario}_$fecha"
    
    mkdir -p "$dir_destino"
    
    # Copiar archivos manteniendo estructura
    while IFS='|' read -r archivo _ _ _; do
        local dir_archivo=$(dirname "$archivo")
        mkdir -p "$dir_destino$dir_archivo"
        cp -a "$archivo" "$dir_destino$dir_archivo/" 2>/dev/null
    done < "${TEMP_RESULTS}_full"

    zenity --info --title="Backup Completado" \
           --text="Se creó backup en: $dir_destino" \
           2>/dev/null
}

# Función para cambiar permisos masivamente
cambiar_permisos_masivo() {
    local usuario="$1"
    local permisos=$(zenity --entry --title="Cambiar Permisos Masivos" \
        --text="Ingrese los permisos en formato octal (ej: 755) para los archivos de $usuario:" \
        --entry-text="644" 2>/dev/null)
    [ -z "$permisos" ] && return

    # Validar formato
    if [[ ! "$permisos" =~ ^[0-7]{3,4}$ ]]; then
        zenity --error --title="Error" --text="Formato de permisos inválido" 2>/dev/null
        return
    fi

    # Procesar cambio
    local contador=0
    while IFS='|' read -r archivo _ _ _; do
        if sudo chmod "$permisos" "$archivo" 2>/dev/null; then
            ((contador++))
            registrar_log "Cambió permisos de $archivo a $permisos (usuario: $usuario)"
        fi
    done < "${TEMP_RESULTS}_full"

    zenity --info --title="Resultado" \
           --text="Se cambiaron permisos de $contador archivos de $usuario a $permisos" \
           2>/dev/null
}

# Función para mover archivos masivamente
mover_archivos_masivo() {
    local usuario="$1"
    local dir_destino=$(zenity --file-selection --directory --title="Seleccione directorio destino" 2>/dev/null)
    [ -z "$dir_destino" ] && return

    # Procesar movimiento
    local contador=0
    while IFS='|' read -r archivo _ _ _; do
        local nombre_archivo=$(basename "$archivo")
        if sudo mv "$archivo" "$dir_destino/$nombre_archivo" 2>/dev/null; then
            ((contador++))
            registrar_log "Movió $archivo a $dir_destino (usuario: $usuario)"
        fi
    done < "${TEMP_RESULTS}_full"

    zenity --info --title="Resultado" \
           --text="Se movieron $contador archivos de $usuario a $dir_destino" \
           2>/dev/null
}

# Función para modificar permisos de múltiples archivos
modificar_permisos() {
    local archivos=$(seleccionar_archivos)
    [ -z "$archivos" ] && return
    
    IFS='|' read -ra lista_archivos <<< "$archivos"
    
    # Mostrar resumen
    zenity --info --title="Archivos Seleccionados" \
           --text="Ha seleccionado ${#lista_archivos[@]} archivo(s)" \
           2>/dev/null
    
    # Seleccionar formato de permisos
    local formato=$(zenity --list --title="Formato de Permisos" \
           --text="Seleccione el formato para cambiar permisos:" \
           --column="ID" --column="Formato" \
           "1" "Octal (ej: 755)" \
           "2" "Simbólico (ej: u+rwx)" \
           2>/dev/null)
    
    local permisos=""
    case "$formato" in
        "1") 
            permisos=$(zenity --entry --title="Permisos Octal" \
                     --text="Ingrese los permisos en formato octal:" \
                     --entry-text="644" 2>/dev/null)
            ;;
        "2")
            permisos=$(zenity --entry --title="Permisos Simbólico" \
                     --text="Ingrese los permisos en formato simbólico:" \
                     --entry-text="u+rw,g+r,o-rwx" 2>/dev/null)
            ;;
        *) return ;;
    esac
    
    [ -z "$permisos" ] && return
    
    # Confirmar operación
    zenity --question --title="Confirmación" \
           --text="¿Aplicar permisos '$permisos' a ${#lista_archivos[@]} archivo(s)?" \
           --ok-label="Aplicar" --cancel-label="Cancelar" \
           2>/dev/null || return
    
    # Procesar cada archivo
    local cambios_exitosos=0
    for archivo in "${lista_archivos[@]}"; do
        if sudo chmod "$permisos" "$archivo" 2>/dev/null; then
            ((cambios_exitosos++))
            registrar_log "Modificó permisos de $archivo a $permisos"
        fi
    done
    
    zenity --info --title="Resultado" \
           --text="Operación completada:\n\nÉxitos: $cambios_exitosos\nFallidos: $((${#lista_archivos[@]} - cambios_exitosos))" \
           2>/dev/null
}

# Menú principal para administradores
menu_admin() {
    while true; do
        local opcion=$(zenity --list --title="Gestor de Archivos (Modo Admin)" \
            --text="Seleccione una operación:" \
            --column="ID" --column="Opción" --column="Descripción" \
            "1" "Buscar archivos por usuario" "Encontrar y gestionar archivos de un usuario específico" \
            "2" "Modificar permisos" "Cambiar permisos de archivos/directorios" \
            "3" "Ver logs" "Consultar registro de actividades" \
            "4" "Salir" "Terminar la aplicación" \
            --width=800 --height=400 2>/dev/null)
        
        case "$opcion" in
            "1") buscar_por_usuario ;;
            "2") modificar_permisos ;;
            "3") ver_logs ;;
            "4") break ;;
            *) zenity --error --text="Opción no válida" 2>/dev/null ;;
        esac
    done
}

# Función para ver logs
ver_logs() {
    local log_file="$([ $EUID -eq 0 ] && echo "$LOG_GLOBAL" || echo "$LOG_USUARIO")"
    
    local opcion=$(zenity --list --title="Visualización de Logs" \
        --text="Seleccione una opción:" \
        --column="ID" --column="Opción" \
        "1" "Últimas entradas" \
        "2" "Buscar por usuario" \
        "3" "Exportar logs" \
        2>/dev/null)
    
    case "$opcion" in
        "1") 
            contenido=$(tail -20 "$log_file")
            zenity --text-info --title="Últimas entradas" \
                   --filename=<(echo "$contenido") \
                   --width=800 --height=600 2>/dev/null
            ;;
        "2")
            local usuario=$(zenity --entry --title="Filtrar por usuario" \
                                  --text="Ingrese el nombre de usuario:" 2>/dev/null)
            if [ -n "$usuario" ]; then
                contenido=$(grep "Usuario: $usuario" "$log_file")
                zenity --text-info --title="Resultados para $usuario" \
                       --filename=<(echo "$contenido") \
                       --width=800 --height=600 2>/dev/null
            fi
            ;;
        "3")
            local archivo_salida=$(zenity --file-selection --save \
                                         --title="Guardar logs como..." \
                                         --filename="logs_$(date +%Y%m%d).txt" 2>/dev/null)
            if [ -n "$archivo_salida" ]; then
                cp "$log_file" "$archivo_salida" && \
                zenity --info --title="Éxito" \
                       --text="Logs exportados a $archivo_salida" 2>/dev/null
            fi
            ;;
    esac
}

# Inicialización
crear_logs

# Verificar si es administrador
if [[ $EUID -eq 0 ]]; then
    menu_admin
else
    zenity --info --title="Acceso denegado" \
           --text="Esta función está disponible solo para administradores" \
           --width=300 2>/dev/null
fi

# Limpieza
rm -f "$TEMP_RESULTS" "${TEMP_RESULTS}_full" 2>/dev/null
