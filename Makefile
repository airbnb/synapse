build: synapse.jar

synapse.jar:
	jruby -S warble jar

.PHONY: build push
