#!/bin/sh

cd -- "$(dirname "$BASH_SOURCE")"

function show_menu() {

  if [[ $PWD = ~/.config/mpv ]]
  then
      echo "================================================"
      green "您正确安放相关配置文件到 ~/.config/mpv 目录, "
      green "无需再次运行该脚本，已自动退出脚本"
      echo "================================================"
      exit 1
  else
      echo "================================================"
      echo "  是否用当前文件夹内容覆盖 \033[31m~/.config/mpv\033[0m 目录？"
      echo "================================================"
  fi
}

function red() {
  echo "\033[31m${1}\033[0m"
}

function green() {
  echo "\033[32m${1}\033[0m"
}

# 参数1: 成功与否$0
# 参数2: 文件名
function echo_result() {
  if [ $1 -eq 0 ]; then
    green "-----------------------------------------------------"
    green "  ${2}\t\t【 成功 】 "
    green "  mpv相关配置文件已安装到指定文件夹"

  else
    red "${2}\t\t 【 失败 】"
    echo "请手动移动文件到 ~/.config/mpv 文件夹"
  fi
}

show_menu

echo "  请选择 \033[32my: 执行\033[0m  \033[31mn: 取消\033[0m: \c"
read choice

case $choice in
y)
  if [ ! -d "~/.config/mpv" ]; then # 如果不存在 .config/mpv 目录
    mkdir ~/.config/mpv
  fi
  rm -Rf ~/.config/mpv/*  
  cp -Rf ./* ~/.config/mpv/
  rm -Rf ~/.config/mpv/*.command
  if [ ! -L "/usr/local/bin/yt-dlp" ]; then # 如果yt-dlp没加入环境变量
    ln -s ~/.config/mpv/yt-dlp /usr/local/bin
  fi
  if [ ! -L "/usr/local/mpv" ]; then # 如果mpv没加入环境变量
    sudo ln -s /Applications/mpv.app/Contents/MacOS/mpv /usr/local
  fi

  echo_result $? "复制文件到 ~/.config/mpv 目录"
  ;;
n)
  echo "================================================"
  green "已取消操作"
  exit
  ;;

esac
