# linux-cli
个人使用的Linux下开发环境安装脚本

## sshkey
```sh
# 将备份的 key 复制到 $HOME/.ssh
# 设置权限
chmod 755 .ssh
chmod 600 .ssh/id_*

# 以现以下错误时
# sign_and_send_pubkey: signing failed: agent refused operation
eval "$(ssh-agent -s)"
ssh-add
```
