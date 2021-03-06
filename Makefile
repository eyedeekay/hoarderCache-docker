dummy: .get-addons
	@echo "$(username)"
	@echo "$(password)"
	@echo "$(working_directory)"
	@echo "$(cache_directory)"
	@echo "$(import_directory)"

include config.mk

push:
	gpg --batch --yes --clear-sign -u "$(SIGNING_KEY)" \
		README.md
	git add .
	git commit -am "$(DEV_MESSAGE)"
	git push

update:
	git pull

update-build:
	make update
	make all

update-all: update all restart addon-update

all:
	mkdir -p "$(cache_directory)" "$(import_directory)"
	chmod a+w "$(cache_directory)"
	chmod a+w "$(import_directory)"
	make build
	make offline-build
	docker system prune -f

build:
	docker build -f Dockerfiles/Dockerfile.acng-base \
		 --build-arg "acng_password=$(password)" \
		--build-arg "CACHING_PROXY=$(proxy_addr)" \
		-t eyedeekay/acng-base .
	docker build -f Dockerfiles/Dockerfile.acng-devuan \
		-t eyedeekay/acng-devuan .
	docker build -f Dockerfiles/Dockerfile.acng-i2p \
		-t eyedeekay/acng-i2p .
	docker build -f Dockerfiles/Dockerfile.acng-tor \
		-t eyedeekay/acng-tor .
	docker build -f Dockerfiles/Dockerfile.acng-syncthing \
		-t eyedeekay/acng-syncthing .
	docker build -f Dockerfiles/Dockerfile.acng-tox \
		-t eyedeekay/acng-tox .
	docker build -f Dockerfiles/Dockerfile.acng-eyedeekay \
		-t eyedeekay/acng-eyedeekay .
	make online-build

network:
	docker network create apthoarder; true

online-build:
	docker build -f Dockerfiles/Dockerfile.acng-online \
		-t eyedeekay/acng .

offline-build:
	docker build --build-arg "acng_password=$(password)" \
		--build-arg "CACHING_PROXY=$(proxy_addr)" \
		-f Dockerfiles/Dockerfile.acng-offline \
		-t eyedeekay/acng-offline .

enter:
	docker exec -i -t hoardercache bash

restart: network
	docker rm -f apthoarder-site; \
	make run-daemon

run: run-daemon
	#offline-run-daemon

run-daemon: network
	docker run -d \
		--network apthoarder \
		--network-alias apthoarder-site \
		--hostname apthoarder-site \
		--link apthoarder-host \
		-p 0.0.0.0:3142:3142 \
		--restart=always \
		--volume "$(cache_directory)":/var/cache/apt-cacher-ng \
		--volume "$(import_directory)":/var/cache/apt-cacher-ng/_import \
		--volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
		--name apthoarder-site \
		-t eyedeekay/acng

offline-run-daemon: network
	docker run -d \
		--network apthoarder \
		--network-alias apthoarder-site-offline \
		--hostname apthoarder-site-offline \
		--link apthoarder-host \
		-p 0.0.0.0:3143:3143 \
		--restart=always \
		--volume "$(cache_directory)":/var/cache/apt-cacher-ng \
		--volume "$(import_directory)":/var/cache/apt-cacher-ng/_import \
		--volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
		--name apthoarder-site-offline \
		-t eyedeekay/acng-offline

get-pw:
	docker exec -t hoardercache cat /etc/apt-cacher-ng/security.conf | sed 's|AdminAuth: acng:||'

launcher:
	@echo "#! /bin/bash" | tee /bin/launcher.sh
	@echo "chmod 777 /var/cache/apt-cacher-ng" | tee -a /bin/launcher.sh
	@echo "/etc/init.d/apt-cacher-ng start" | tee -a /bin/launcher.sh
	@echo "tail -f /var/log/apt-cacher-ng/*" | tee -a /bin/launcher.sh
	chmod a+x /bin/launcher.sh

online:
	docker exec hoardercache sed -i 's|offlinemode:1|offlinemode:0|g'
	docker exec hoardercache /etc/init.d/apt-cacher-ng restart

offline:
	docker exec hoardercache sed -i 's|offlinemode:0|offlinemode:1|g'
	docker exec hoardercache /etc/init.d/apt-cacher-ng restart

clobber:
	docker system prune -f; \
	docker rm -f base-apt-cache; \
	docker rmi -f hoardercache; \
	true

clobber-all: clobber addon-clobber

curljob:
	\curl -u acng:"$(shell docker exec -t hoardercache cat /etc/apt-cacher-ng/security.conf | sed 's|AdminAuth: acng:||')" \
	  'http://192.168.1.98:3142/acng-report.html?abortOnErrors=aOe&doImport=Start+Import&calcSize=cs&asNeeded=an'

install-curljob:
	echo "#! /usr/bin/env sh" | sudo tee /usr/local/bin/scheduled-cacher-import
	echo "pw=\$$(docker exec -t hoardercache cat /etc/apt-cacher-ng/security.conf | sed 's|AdminAuth: acng:||')" | sudo tee -a /usr/local/bin/scheduled-cacher-import
	echo "echo \"$pw\"" | sudo tee -a /usr/local/bin/scheduled-cacher-import
	echo "curl -u acng:\"\$$(docker exec -t hoardercache cat /etc/apt-cacher-ng/security.conf | sed 's|AdminAuth: acng:||')\" \\" | sudo tee -a /usr/local/bin/scheduled-cacher-import
	echo "  'http://192.168.1.98:3142/acng-report.html?abortOnErrors=aOe&doImport=Start+Import&calcSize=cs&asNeeded=an'" | sudo tee -a /usr/local/bin/scheduled-cacher-import
	echo "" | sudo tee -a /usr/local/bin/scheduled-cacher-import
	sudo chmod +x /usr/local/bin/scheduled-cacher-import
	crontab -l | { cat; echo "15 * * * * scheduled-cacher-import"; } | crontab -


