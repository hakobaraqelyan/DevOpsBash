#!/usr/bin/env bash


gnome-terminal -- bash -c "
cd /home/hakob/Projects/Report_server || exit
code .
npm run dev
exec bash
"

gnome-terminal -- bash -c "
cd /home/hakob/Projects/Report || exit
code .
npm start
exec bash
"

google-chrome &

exit 0