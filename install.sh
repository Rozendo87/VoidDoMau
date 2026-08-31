#!/bin/bash
# BY:  MAUVADAO
# VER: 1.0.1

set -e

repo="https://github.com/Rozendo87/VoidDoMau.git"
dir="$(basename "$repo" .git)"

if [ -d "$dir" ]; then
	echo "Pasta '$dir' ja existe, atualizando..."
	cd "$dir"
	git pull
else
	git clone "$repo" "$dir"
	cd "$dir"
fi

if [ -f install.sh ]; then
	chmod +x install.sh
	bash install.sh "$@"
else
	echo "Install nao encontrado"
	exit 1
fi
