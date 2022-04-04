ARG atlantis_version=dev

FROM golang:1.17.3 as helmfile-builder

# tag: v0.143.0
ARG helmfile_base_ref="9e9a90f8ef30ec0f0f3e03e2f69fb4703c7e7831"

ENV CGO_ENABLED=0

WORKDIR /build

RUN git config --global user.email "leandro@carnei.ro" \
    && git config --global user.name "carnei-ro" \
    && git clone https://github.com/roboll/helmfile.git

WORKDIR /build/helmfile

RUN git checkout "${helmfile_base_ref}" \
    && find . -type f -iname "*.go" -exec sed -i "s|github.com/variantdev/vals|github.com/carnei-ro/vals|g" {} \; \
    && sed -i 's|github.com/variantdev/vals v0.15.0|github.com/carnei-ro/vals v0.16.0|g' go.mod \
    && go mod download github.com/carnei-ro/vals \
    && go mod download github.com/fujiwara/tfstate-lookup \
    && go build -o helmfile ./main.go

FROM golang:1.16 as vals-builder

ARG vals_base_ref="master"

ENV CGO_ENABLED=0

WORKDIR /build

RUN git config --global user.email "leandro@carnei.ro" \
    && git config --global user.name "carnei-ro" \
    && git clone https://github.com/variantdev/vals

WORKDIR /build/vals

RUN git checkout "${vals_base_ref}" \
    && git remote add carnei-ro https://github.com/carnei-ro/vals.git \
    && git fetch --all \
    && git merge --no-ff --no-edit carnei-ro/feat/tfstate/remote \
    && go build -o bin/vals ./cmd/vals

FROM alpine:3.11 as downloader

RUN apk add --no-cache curl

ARG TARGETARCH="arm64"

ARG terragrunt_version="v0.36.6"
ARG infracost_version="v0.9.21"

ARG helm_version="3.8.1"
ARG helmfile_version="0.143.0"
ARG kubectl_version="1.21.11"
ARG kustomize_version="3.10.0"
ARG tfstate_lookup_version="0.4.2"

ENV TERRAGRUNT_VERSION="${terragrunt_version}" \
    INFRACOST_VERSION="${infracost_version}"

RUN set -ex \
    && wget -q -O helm.tar.gz \
        "https://get.helm.sh/helm-v${helm_version}-linux-${TARGETARCH}.tar.gz" \
    && tar -xzvf helm.tar.gz \
    && rm -f helm.tar.gz \
    && mv linux-${TARGETARCH}/helm /usr/local/bin/helm \
    && chown -v root:root /usr/local/bin/helm \
    && chmod -v 755 /usr/local/bin/helm

# RUN set -ex \
#     && wget -q -O helmfile \
#         "https://github.com/roboll/helmfile/releases/download/v${helmfile_version}/helmfile_linux_${TARGETARCH}" \
#     && mv helmfile /usr/local/bin/helmfile \
#     && chown -v root:root /usr/local/bin/helmfile \
#     && chmod -v 755 /usr/local/bin/helmfile

RUN set -ex \
    && wget -q -O kubectl \
        "https://dl.k8s.io/release/v${kubectl_version}/bin/linux/${TARGETARCH}/kubectl" \
    && mv kubectl /usr/local/bin/kubectl \
    && chown -v root:root /usr/local/bin/kubectl \
    && chmod -v 755 /usr/local/bin/kubectl

RUN set -ex \
    && wget -q -O kustomize.tar.gz \
        "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${kustomize_version}/kustomize_v${kustomize_version}_linux_${TARGETARCH}.tar.gz" \
    && tar -xzvf kustomize.tar.gz \
    && rm -f kustomize.tar.gz \
    && mv kustomize /usr/local/bin/kustomize \
    && chown -v root:root /usr/local/bin/kustomize \
    && chmod -v 755 /usr/local/bin/kustomize

RUN set -ex \
    && wget -q -O tfstate-lookup.tar.gz \
        "https://github.com/fujiwara/tfstate-lookup/releases/download/v${tfstate_lookup_version}/tfstate-lookup_${tfstate_lookup_version}_linux_${TARGETARCH}.tar.gz" \
    && tar -xzvf tfstate-lookup.tar.gz \
    && rm -f tfstate-lookup.tar.gz \
    && mv tfstate-lookup /usr/local/bin/tfstate-lookup \
    && chown -v root:root /usr/local/bin/tfstate-lookup \
    && chmod -v 755 /usr/local/bin/tfstate-lookup

RUN set -ex \
    && curl -sL "https://github.com/gruntwork-io/terragrunt/releases/download/${TERRAGRUNT_VERSION}/terragrunt_linux_${TARGETARCH}" --output terragrunt \
    && chmod +x terragrunt \
    && mv terragrunt /usr/local/bin

RUN set -ex \
    && curl -sL "https://github.com/infracost/infracost/releases/download/${INFRACOST_VERSION}/infracost-linux-${TARGETARCH}.tar.gz" --output infracost.tar.gz \
    && tar xf infracost.tar.gz \
    && chmod +x "infracost-linux-${TARGETARCH}" \
    && mv "infracost-linux-${TARGETARCH}" /usr/local/bin/infracost

FROM ghcr.io/runatlantis/atlantis:${atlantis_version} as atlantis

ARG TARGETARCH="amd64"

LABEL org.opencontainers.image.description "Atlantis server with Terragrunt, InfraCost, Helmfile, Helm, Kubectl and other add-ons."

COPY --from=vals-builder /build/vals/bin/vals /usr/local/bin/vals
COPY --from=helmfile-builder /build/helmfile/helmfile /usr/local/bin/helmfile

COPY --from=downloader /usr/local/bin/helm /usr/local/bin/helm
# COPY --from=downloader /usr/local/bin/helmfile /usr/local/bin/helmfile
COPY --from=downloader /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=downloader /usr/local/bin/kustomize /usr/local/bin/kustomize
COPY --from=downloader /usr/local/bin/tfstate-lookup /usr/local/bin/tfstate-lookup
COPY --from=downloader /usr/local/bin/terragrunt /usr/local/bin/terragrunt
COPY --from=downloader /usr/local/bin/infracost /usr/local/bin/infracost

RUN set -ex \
    && apk add --no-cache curl jq \
    && mkdir -p ~/.config/kustomize/plugin/v1/none \
    && helm plugin install https://github.com/databus23/helm-diff \
    && helm plugin install https://github.com/aslafy-z/helm-git \
    && helm plugin install https://github.com/jkroepke/helm-secrets \
    && deluser "atlantis" \
    && addgroup -g 1000 "atlantis" \
    && adduser -h "/home/atlantis" -D -u 100 -G "atlantis" "atlantis"

USER atlantis

RUN set -ex \
    && mkdir -p ~/.config/kustomize/plugin/v1/none \
    && helm plugin install https://github.com/databus23/helm-diff \
    && helm plugin install https://github.com/aslafy-z/helm-git \
    && helm plugin install https://github.com/jkroepke/helm-secrets

USER root

COPY hack/format-diff-output.sh /usr/local/bin/format-diff-output.sh
COPY hack/patch-terraform-cloud-workspace-execution-mode.sh /usr/local/bin/patch-terraform-cloud-workspace-execution-mode.sh
