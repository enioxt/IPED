#!/bin/bash
# IPED Linux GUI Launcher — Anti-Freeze Mode
# Solves the Wayland/X11 multi-monitor splash screen freeze by bypassing the native JVM splash
# Ensure you are running this from the IPED root or pass the release directory.

RELEASE_DIR=${1:-"target/release/iped-4.4.0-SNAPSHOT"}
SEARCH_JAR="$RELEASE_DIR/lib/iped-search-app.jar"

if [ ! -f "$SEARCH_JAR" ]; then
    echo "Erro: UI JAR não encontrado em $SEARCH_JAR"
    echo "Por favor, compile o IPED primeiro ou passe o caminho da pasta de release como argumento:"
    echo "./iped-ui.sh /caminho/para/iped-x.y.z"
    exit 1
fi

echo "Iniciando explorador visual (IPED Search App)..."
echo "Bypassing Native Splash Screen para evitar travamentos no Linux..."

# The -nosplash argument prevents the JVM from rendering the Manifest splash image
# which is known to freeze/deadlock on certain Linux graphical servers (Wayland).
java -nosplash -jar "$SEARCH_JAR" "$@"
