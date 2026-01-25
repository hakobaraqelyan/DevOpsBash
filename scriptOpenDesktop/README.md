# Open Apps in login

vim ~/bin/dev-startup.sh # script file
chmod +x ~/bin/dev-startup.sh
mkdir -p ~/.config/systemd/user
vim ~/.config/systemd/user/dev-startup.service

    [Unit]
    Description=Start my dev environment
    After=graphical-session.target

    [Service]
    Type=oneshot
    ExecStart=/home/hakob/bin/dev-startup.sh
    RemainAfterExit=true

    [Install]
    WantedBy=default.target

systemctl --user daemon-reload
systemctl --user enable dev-startup.service
systemctl --user start dev-startup.service
