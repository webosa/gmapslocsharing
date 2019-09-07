#!/bin/bash
#
## -------------------------------=[ Info ]=--------------------------------- ##
#
## -=[ Author ]=------------------------------------------------------------- ##
#
# shr00mie
# 09.03.2019
# v0.5
#
## -=[ Use Case ]=----------------------------------------------------------- ##
#
# Appends google-chrome-stable install to base homeassistant Dockerfile.
#
## -=[ Breakdown ]=---------------------------------------------------------- ##
#
# 1. Create directories.
# 2. Clone custom component elements into build directory.
# 3. Copy custom_components and deps folders into HA mount (config) directory.
# 4. Generate custom Dockerfile to build directory.
# 5. Generate sample docker-compose.yaml file to base HA directory.
# 6. Set permissions on base HA directory.
# 7. Build custom image as hasschrome:latest
#
## -=[ To-Do ]=-------------------------------------------------------------- ##
#
# I'm sure a bunch...
#
## -=[ Requirements & Assumptions ]=----------------------------------------- ##

# The following assumptions are being made:
#   - dependencies:
#     - docker-ce and git are installed
#   - users & groups:
#     - your user is a member of docker group (sudo usermod -aG docker $USER)
#   - volumes:
#     - the persitent volumes for your containers exist under $HOME/docker.
#       if that's not the case, make the necessary changes to DirDocker below.
#   - docker:
#     - you are using a docker-compose.yaml file located under $HOME/docker
#     - the docker-compose service name is "homeassistant"

## -=[ Functions ]=---------------------------------------------------------- ##
#
# Usage: status "Status Text"
function status() {
  GREEN='\033[00;32m'
  RESTORE='\033[0m'
  echo -e "\n...${GREEN}$1${RESTORE}...\n"
}
#
## -----------------------------=[ Variables ]=------------------------------ ##

# user for docker mount
DockerUser="$USER"
# grabs user ID
DockerUserID="$(id -u)"
# group for docker mount
DockerGroup="docker"
# grabs docker group ID
DockerGroupID="$(cat /etc/group | grep docker | cut -d: -f3)"

# Docker container/service name
ContainerName="homeassistant"

# Temp Files
DirTemp="$HOME/temp"
# Docker Directory
DirDocker="$HOME/docker"
# HA Docker Directory
DirHA="$DirDocker/hass"
# docker-compose path:
DockerComposeBase="$DirDocker"
DockerComposeFile="docker-compose.yaml"
DockerCompose="$DockerComposeBase/$DockerComposeFile"

# HA container config directory
HA_Config="/config"
# HA container working directory
HA_App="/usr/src/app"

## ---------------------------=[ Script Start ]=----------------------------- ##

status "Checking folders."
folders=($DirTemp $DirDocker $DirHA)
for i in ${folders[@]}
do
  if [[ ! -d $i ]]; then
      echo "Creating $i folder."
      mkdir -p $i
  fi
done

status "Cloning gmapslocsharing docker repo to $DirTemp"
git clone https://github.com/shr00mie/gmapslocsharing.git -b docker $DirTemp
cp -r $DirTemp/custom_components $DirTemp/deps $DirHA

status "Setting user:group on $DirHA"
sudo chown -R $DockerUser:$DockerGroup $DirHA

status "Setting permissions on $DirHA"
sudo chmod -R u=rwX,g=rwX,o=--- $DirHA

status "Setting ACLs on $DirHA"
sudo setfacl -R -m d:u:$DockerUser:rwX,d:g:$DockerGroup:rwX,d:o::--- $DirHA

status "Generating docker-entrypoint.sh to: $DirTemp"
cat << EOF | tee $DirTemp/docker-entrypoint.sh > /dev/null
#!/bin/bash
set -e

python3 -m homeassistant -c $HA_Config --script check_config
exec gosu $DockerUser:$DockerGroup "\$@"
EOF

status "Generating Dockerfile to: $DirTemp"
cat << EOF | tee $DirTemp/Dockerfile > /dev/null
FROM homeassistant/home-assistant:latest
LABEL maintainer="shr00mie"

COPY docker-entrypoint.sh $HA_App/docker-entrypoint.sh

RUN apk update && apk upgrade && \
    echo @edge http://nl.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories && \
    echo @edge http://nl.alpinelinux.org/alpine/edge/main >> /etc/apk/repositories && \
    echo @edge http://nl.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories && \
    apk add --no-cache \
      python3@edge \
      python3-dev@edge \
      acl@edge \
      gosu@edge \
      chromium@edge \
      chromium-chromedriver@edge \
      nss@edge \
      freetype@edge \
      freetype-dev@edge \
      harfbuzz@edge \
      ttf-freefont@edge && \
    pip3 install -U pip setuptools wheel

RUN addgroup --gid $DockerGroupID $DockerGroup && \
    adduser --system --uid $DockerUserID --ingroup $DockerGroup $DockerUser && \
    addgroup $DockerUser dialout

RUN chmod -R u=rwX,g=rwX,o=--- $HA_Config && \
    chmod +x $HA_App/docker-entrypoint.sh && \
    chown -R $DockerUser:$DockerGroup $HA_Config /home/$DockerUser

RUN setfacl -R -m d:u:$DockerUser:rwX,d:g:$DockerGroup:rwX,d:o::--- $HA_Config

ENTRYPOINT ["$HA_App/docker-entrypoint.sh"]
CMD ["python3","-m","homeassistant","-c","$HA_Config"]
EOF

status "Stopping homeassistant"
docker stop $ContainerName

status "Docker cleanup"
docker image prune -f && docker container prune -f && docker volume prune -f

status "Building hass-chrome image"
docker build --no-cache --label=hass-chrome --tag=hass-chrome:latest $DirTemp

status "Starting HA container"
docker-compose -f $DockerCompose up -d $ContainerName

status "Performing cleanup"
rm -rf $DirTemp
