#!/bin/bash

echo "This is for my FG Steam path under Linux, you will have to adjust this"
exit

cd EncounterDifficulty
zip -r ../EncounterDifficulty.ext .
cd ..
cp EncounterDifficulty.ext "/home/leslie/.steam/debian-installation/steamapps/compatdata/1196310/pfx/drive_c/users/steamuser/AppData/Roaming/SmiteWorks/Fantasy Grounds/extensions"
