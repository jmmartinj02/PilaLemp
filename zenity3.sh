#!/bin/bash

# Configuración
LOG_GLOBAL="/var/log/gestor_archivos.log"
LOG_USUARIO="$HOME/gestor_archivos_user.log"
TEMP_RESULTS="/tmp/gestor_archivos.tmp"

# Función para crear logs
crear_logs() {
    # Solo root puede crear el log global
    if [[ $EUID -eq 0 ]]; then
        [ ! -f "$LOG_GLOBAL" ] && { touch "$LOG_GLOBAL"; chmod 600 "$LOG_GLOBAL"; }
    fi
    # Todos los usuarios tienen su log local
    [ ! -f "$LOG_USUARIO" ] && { touch "$LOG_USUARIO"; chmod 600 "$LOG_USUARIO"; }
}

# Función de registro mejorada
registrar_log() {
    local mensaje="[$(date '+%Y-%m-%d %H:%M:%S')] Usuario: $(whoami) - $1"
    
    # Registro local obligatorio
    echo "$mensaje" >> "$LOG_USUARIO"
    
    # Registro global (intentamos siempre)
    if [[ $EUID -eq 0 ]]; then
        echo "$mensaje" >> "$LOG_GLOBAL"
    else
        # Método alternativo sin tee
        sudo sh -c "echo '$mensaje' >> '$LOG_GLOBAL'" 2>/dev/null || true
    fi
}

# Función para procesar resultados de búsqueda
procesar_resultados() {
    local usuario="$1"
    
    # Buscar archivos con formato: ruta|usuario|grupo|permisos|tamaño
    find / -user "$usuario" -printf '%p|%u|%g|%m|%s\n' 2>/dev/null > "${TEMP_RESULTS}_full"
    
    if [ ! -s "${TEMP_RESULTS}_full" ]; then
        zenity --info --title="Resultados" --text="No se encontraron archivos" 2>/dev/null
        return 1
    fi
    
    # Procesar cada línea correctamente
    while IFS='|' read -r ruta usuario grupo permisos tamano; do
        echo "$ruta|$usuario|$grupo|$permisos|$((tamano/1024))KB" >> "$TEMP_RESULTS"
    done < "${TEMP_RESULTS}_full"
    
    return 0
}

# Función para cambiar propietario
cambiar_propietario() {
    local archivos="$1"
    local nuevo_prop=$(zenity --entry --title="Nuevo Propietario" \
                            --text="Ingrese usuario:grupo nuevo:" 2>/dev/null)
    [ -z "$nuevo_prop" ] && return
    
    # Contadores para el resultado
    local exitos=0 fallos=0
    
    # Procesar cada archivo
    while IFS='|' read -r ruta _ _ _; do
        if sudo chown "$nuevo_prop" "$ruta" 2>/dev/null; then
            ((exitos++))
            registrar_log "Cambió propietario de $ruta a $nuevo_prop"
        else
            ((fallos++))
        fi
    done <<< "$archivos"
    
    # Mostrar resumen
    zenity --info --title="Resultado" \
           --text="Operación completada:\n\nÉxitos: $exitos\nFallidos: $fallos" \
           2>/dev/null
}

# Función principal para administradores
menu_admin() {
    while true; do
        opcion=$(zenity --list --title="Gestor de Archivos (Admin)" \
            --text="Seleccione una operación:" \
            --column="ID" --column="Acción" \
            "1" "Gestionar archivos por usuario" \
            "2" "Ver logs globales" \
            "3" "Salir" 2>/dev/null)
        
        case "$opcion" in
            "1")
                usuario=$(zenity --entry --title="Usuario a gestionar" \
                               --text="Ingrese el nombre de usuario:" 2>/dev/null)
                [ -z "$usuario" ] && continue
                
                if procesar_resultados "$usuario"; then
                    # Mostrar opciones para los archivos encontrados
                    opcion_accion=$(zenity --list --title="Acciones para $usuario" \
                        --text="Se encontraron $(wc -l < "$TEMP_RESULTS") archivos" \
                        --column="ID" --column="Acción" \
                        "1" "Cambiar propietario" \
                        "2" "Cambiar permisos" \
                        "3" "Eliminar archivos" 2>/dev/null)
                    
                    # Leer todos los archivos encontrados
                    archivos=$(cat "$TEMP_RESULTS")
                    
                    case "$opcion_accion" in
                        "1") cambiar_propietario "$archivos" ;;
                        # Aquí irían las otras funciones...
                    esac
                fi
                ;;
            "2") ver_logs ;;
            "3") break ;;
        esac
    done
}

# Inicialización
crear_logs

if [[ $EUID -eq 0 ]]; then
    menu_admin
else
    zenity --error --title="Acceso denegado" \
           --text="Esta herramienta es solo para administradores" \
           2>/dev/null
fi

# Limpieza
rm -f "$TEMP_RESULTS" "${TEMP_RESULTS}_full" 2>/dev/null
