#!/bin/bash
# MAUVADAO
# Versão: 1.0.8
# Script para adicionar, commitar e enviar alterações ao Git
# Usa chave SSH específica para o GitHub

clear

# ============================================================
# CONFIGURAÇÕES
# ============================================================

# Usuário do sistema
usuario="$(whoami)"

# Chave SSH usada pelo GitHub
chave_git="$HOME/.ssh/chmod665"

# ============================================================
# FUNÇÕES
# ============================================================

_maudavpn() {
    local palavra="$1"

    local banner
    banner=$(figlet "$palavra" 2>/dev/null)

    local largura
    largura=$(echo "$banner" | awk '{ if (length > max) max = length } END { print max }')

    local linha
    linha=$(printf '%*s' "$largura" '' | tr ' ' '-')

    echo -e "\e[1;37m $linha\e[0m"
    echo -e "\e[1;38;5;153m$banner\e[0m"
    echo -e "\e[1;37m $linha\e[0m"
}

msg() {
    local color="$1"
    local text="$2"

    case "$color" in
        green)
            tput setaf 2 2>/dev/null
            ;;
        yellow)
            tput setaf 3 2>/dev/null
            ;;
        red)
            tput setaf 1 2>/dev/null
            ;;
        *)
            tput sgr0 2>/dev/null
            ;;
    esac

    echo "$text"
    tput sgr0 2>/dev/null
}

# ============================================================
# INFORMAÇÕES DO REPOSITÓRIO
# ============================================================

pasta="$(pwd)"

_maudavpn "${1:-$(basename "$pasta")}"

# ============================================================
# VERIFICA DEPENDÊNCIAS
# ============================================================

command -v git >/dev/null 2>&1 || {
    msg red "Erro: Git não está instalado."
    exit 1
}

command -v ssh >/dev/null 2>&1 || {
    msg red "Erro: SSH não está instalado."
    exit 1
}

# ============================================================
# VERIFICA CHAVE SSH
# ============================================================

if [[ ! -f "$chave_git" ]]; then
    msg red "Erro: chave SSH não encontrada:"
    echo "$chave_git"
    exit 1
fi

# Permissão recomendada para chave privada
chmod 600 "$chave_git" 2>/dev/null

# ============================================================
# VERIFICA SE É UM REPOSITÓRIO GIT
# ============================================================

_verificar_git() {

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        msg red "[!] Esta pasta não é um repositório Git."
        exit 1
    fi

    BRANCH="$(git branch --show-current)"

    if [[ -z "$BRANCH" ]]; then
        msg red "[!] Não conseguiu detectar a branch."
        exit 1
    fi

    msg green "[*] Branch: $BRANCH"
}

_verificar_git

# ============================================================
# CONFIGURAÇÃO DO GIT
# ============================================================

git_user_name="$(git config --local user.name 2>/dev/null)"
git_user_email="$(git config --local user.email 2>/dev/null)"

# Se não existir configuração local, tenta global
[[ -z "$git_user_name" ]] && \
    git_user_name="$(git config --global user.name 2>/dev/null)"

[[ -z "$git_user_email" ]] && \
    git_user_email="$(git config --global user.email 2>/dev/null)"

# Se ainda não existir, usa o usuário do sistema
[[ -z "$git_user_name" ]] && \
    git_user_name="$usuario"

# ============================================================
# REMOTE
# ============================================================

link="$(git remote get-url origin 2>/dev/null)"

if [[ -z "$link" ]]; then
    msg red "Erro: remote 'origin' não encontrado."
    exit 1
fi

# ============================================================
# FORÇA O SSH A USAR A CHAVE CORRETA
# ============================================================

export GIT_SSH_COMMAND="ssh -i \"$chave_git\" -o IdentitiesOnly=yes"

# ============================================================
# VERIFICA CONEXÃO SSH COM GITHUB
# ============================================================

verificar_ssh_github() {

    echo
    echo "Verificando conexão SSH com o GitHub..."
    echo "Usuário do sistema : $usuario"
    echo "Chave SSH          : $chave_git"
    echo

    ssh_saida="$(
        ssh \
            -i "$chave_git" \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=accept-new \
            -T git@github.com 2>&1
    )"

    ssh_status=$?

    echo "$ssh_saida"

    if [[ "$ssh_status" -eq 1 ]] &&
       grep -qiE 'successfully authenticated|successfully authenticated' <<< "$ssh_saida"; then

        msg green "✓ SSH autenticado com sucesso no GitHub."

    else
        msg red "✗ Falha na autenticação SSH com o GitHub."
        echo
        echo "Verifique:"
        echo "  Chave: $chave_git"
        echo "  Usuário GitHub"
        echo "  Chave cadastrada no GitHub"
        exit 1
    fi
}

verificar_ssh_github

# ============================================================
# INFORMAÇÕES DO REPOSITÓRIO
# ============================================================

git_info() {

    local tipo="desconhecido"

    if command -v gh >/dev/null 2>&1; then
        tipo="$(gh repo view --json visibility -q '.visibility' 2>/dev/null)"
        [[ -z "$tipo" ]] && tipo="desconhecido"
    fi

    echo
    echo -e "\e[1;33mUsuário sistema: \e[1;37m$usuario\e[0m"
    echo -e "\e[1;33mGit user.name : \e[1;37m$git_user_name\e[0m"
    echo -e "\e[1;33mGit user.email: \e[1;37m$git_user_email\e[0m"
    echo -e "\e[1;33mChave SSH     : \e[1;37m$chave_git\e[0m"
    echo -e "\e[1;33mLink          : \e[1;37m🌐$link\e[0m"
    echo -e "\e[1;33mTipo          : \e[1;37m🔓$tipo\e[0m"
    echo
}

git_info

# ============================================================
# VERIFICA MODIFICAÇÕES
# ============================================================

if [[ -z "$(git status --porcelain)" ]]; then
    echo "Limpo."
    exit 0
else
    echo -e "\e[1;33mAlterações encontradas: \e[1;36m$(basename "$pasta")\e[0m"
fi

# ============================================================
# CRIA NOVA VERSÃO
# ============================================================

_new() {

    local commit="$1"
    local data
    local file
    local num
    local newFile

    data="$(date '+%Y-%m-%d %H:%M:%S')"

    file="$(
        find . -maxdepth 1 -type f -name 'ver[0-9]*' -printf '%f\n' 2>/dev/null |
        sort -V |
        tail -n 1
    )"

    if [[ -z "$file" ]]; then
        num=1
    else
        num="$(grep -Eo '[0-9]+' <<< "$file" | tail -n 1)"
        ((num++))

        export version="$num"

        rm -f -- "$file"
    fi

    [[ -z "$version" ]] && export version="$num"

    newFile="ver$num"

    {
        echo "=========================="
        echo "$(basename "$pasta")"
        echo "Ver: $num"
        echo "Data: $data"
        echo "Update: ${commit:-New Update}"
        echo "=========================="
    } > "$newFile"

    echo "Nova versão atualizada: $newFile"
}

# ============================================================
# COMMIT
# ============================================================

commit="$1"

_new "$commit"

texto="$(cat "ver$version" 2>/dev/null)"

msg yellow "Iniciando o script de automação Git..."

# ============================================================
# GIT ADD
# ============================================================

msg green "Adicionando arquivos ao repositório..."

git add -A || {
    msg red "Erro ao adicionar arquivos."
    exit 1
}

# ============================================================
# VERIFICA SE EXISTE ALGO PARA COMMITAR
# ============================================================

git diff --cached --quiet && {
    msg red "Nada para commitar."
    exit 0
}

# ============================================================
# COMMIT
# ============================================================

commit_msg="$(printf '%s\n%s\n\n%s' \
    "$(date +%d%m%y_%H:%M)" \
    "$commit" \
    "$texto"
)"

git commit \
    -m "$commit_msg" \
    >/dev/null 2>&1 || {
        msg red "Erro ao realizar commit."
        exit 1
    }

# ============================================================
# SAFE DIRECTORY
# ============================================================

DIR="$(pwd)"

git config --global \
    --add safe.directory "$DIR" \
    >/dev/null 2>&1

# ============================================================
# PUSH USANDO EXPLICITAMENTE A CHAVE
# ============================================================

msg green "Enviando alterações para o repositório remoto..."

GIT_SSH_COMMAND="ssh -i \"$chave_git\" -o IdentitiesOnly=yes" \
git push || {
    msg red "Erro ao enviar alterações."
    exit 1
}

# ============================================================
# SUCESSO
# ============================================================

echo
echo -ne "\e[38;5;122mProcesso concluído com sucesso!\e[0m "
echo -ne "\e[38;5;188mCommit:\e[0m "

COMMIT="$(git log --oneline -1)"

echo "$COMMIT"

# ============================================================
# VERIFICA VERSÃO
# ============================================================

if [[ -f "ver$version" ]]; then

    echo -e "\e[1;41;33mAtualizado\e[0m: \e[1;48;37m$version\e[0m"

else

    msg red "Erro: A versão não foi criada corretamente."

fi