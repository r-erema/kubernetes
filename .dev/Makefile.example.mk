HOST_IP=192.168.0.123
DATA_DIR=./.
CLUSTER_NAME=dev-cluster
CLUSTER_USER=cluster-admin
KUBE_API_PORT=6443
DOMAIN=localhost
CA_CERT_PATH=${DATA_DIR}/rootCA.crt
CA_KEY_PATH=${DATA_DIR}/rootCA.key
CSR_PATH=${DATA_DIR}/cluster.csr
CERT_KEY_PATH=${DATA_DIR}/common_cert_key_for_all.key
CERT_PATH=${DATA_DIR}/common_cert_for_all.crt

KUBECONFIG_PATH=${DATA_DIR}/kubeconfig-dev

gen-sa-certs:
	mkdir -p ${DATA_DIR}
	openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
		-subj "/C=BY/ST=Minsk Region/L=Minsk/O=${DOMAIN} Office/CN=${DOMAIN}/subjectAltName=DNS.1=${DOMAIN}" \
		-keyout ${CA_KEY_PATH} -out ${CA_CERT_PATH}
	echo "CA Key ${CA_KEY_PATH} is ready"
	echo "CA Cert ${CA_CERT_PATH} is ready"
	openssl genrsa -out ${CERT_KEY_PATH} 2048
	echo "Cert Key ${CERT_KEY_PATH} is ready"
	openssl req -new -key ${CERT_KEY_PATH} \
		-subj "/C=BY/ST=Minsk Region/L=Minsk/O=${DOMAIN} Office/CN=${DOMAIN}/subjectAltName=DNS.1=${DOMAIN}" \
		-out ${CSR_PATH}
	echo "CSR ${CSR_PATH} is ready"
	printf "subjectAltName=DNS:${DOMAIN}" > tmp-ext-file
	openssl x509 -req -extfile tmp-ext-file -in ${CSR_PATH} -days 365 \
		-CA ${CA_CERT_PATH} \
		-CAkey ${CA_KEY_PATH} \
		-CAcreateserial \
		-out ${CERT_PATH}
	echo "cert ${CERT_PATH} is ready"
	rm tmp-ext-file

trust-ca-cert:
	sudo -S cp ${CA_CERT_PATH} ${CSR_PATH} ${CERT_PATH} /usr/local/share/ca-certificates/
	sudo update-ca-certificates

gen-kubeconfig:
	touch ${KUBECONFIG_PATH}
	kubectl config set-credentials ${CLUSTER_USER} \
		--kubeconfig=${KUBECONFIG_PATH} \
		--client-certificate=${CERT_PATH} \
		--client-key=${CERT_KEY_PATH} \
		--embed-certs=true
	kubectl config set-cluster ${CLUSTER_NAME} \
		--kubeconfig=${KUBECONFIG_PATH} \
		--certificate-authority=${CA_CERT_PATH} \
		--server=https://${DOMAIN}:${KUBE_API_PORT}
	kubectl config set-context ${CLUSTER_NAME} \
		--kubeconfig=${KUBECONFIG_PATH} \
		--cluster=${CLUSTER_NAME} \
		--user=${CLUSTER_USER}
	kubectl config use-context ${CLUSTER_NAME} --kubeconfig=${KUBECONFIG_PATH}

etcd:
	docker run --rm -p 2379:2379 -p 2380:2380 --name etcd quay.io/coreos/etcd:v3.5.1 /usr/local/bin/etcd \
		--name node1 \
		--initial-advertise-peer-urls http://${HOST_IP}:2380 \
		--listen-peer-urls http://0.0.0.0:2380 \
		--advertise-client-urls http://${HOST_IP}:2379 \
		--listen-client-urls http://0.0.0.0:2379 \
		--initial-cluster node1=http://${HOST_IP}:2380 \
		--log-level debug

GOROOT=/usr/local/go
GOPATH=/Users/roman.erema/go
API_SERVER_DEBUG_PORT=62001
CONTROLLER_MANAGER_DEBUG_PORT=62002

debug-api-server:
	go build -o apiserver_debug -gcflags "all=-N -l" k8s.io/kubernetes/cmd/kube-apiserver
	dlv --listen=127.0.0.1:${API_SERVER_DEBUG_PORT} --headless=true --api-version=2 --check-go-version=false --only-same-user=false exec \
		apiserver_debug -- \
			--etcd-servers http://${HOST_IP}:2379 \
			--cert-dir ${DATA_DIR} \
			--tls-private-key-file ${CERT_KEY_PATH} \
			--tls-cert-file ${CERT_PATH} \
			--client-ca-file ${CA_CERT_PATH} \
			--service-account-signing-key-file ${CERT_KEY_PATH} \
			--service-account-key-file ${CERT_PATH} \
			--service-account-issuer https://kube.local

debug-controller-manager:
	go build -o controller_manager_debug -gcflags "all=-N -l" k8s.io/kubernetes/cmd/kube-controller-manager
	dlv --listen=127.0.0.1:${CONTROLLER_MANAGER_DEBUG_PORT} --headless=true --api-version=2 --check-go-version=false --only-same-user=false exec \
		controller_manager_debug -- \
			--kubeconfig ${KUBECONFIG_PATH}
