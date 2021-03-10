# TODO: change image address to correct repo
image = registry.gitlab.com/blockie/tmp-image-registry:letsencrypt-renewer-0.84

build:
	space /run/ -d >release/renewer
	chmod +x release/renewer

build-image:
	docker build -t $(image) .

push-image:
	docker push $(image)

# The buildah target is used to build specifically for podman when running locally
build-image-buildah:
	buildah build-using-dockerfile -t $(image) .

.PHONY: build build-image push-image build-image-buildah
