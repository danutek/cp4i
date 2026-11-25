FROM cp.icr.io/cp/ibm-eventstreams-kafka:12.2.2

# Switch to root to install plugins
USER root

# Create plugin directory if it doesn't exist
RUN mkdir -p /opt/kafka/plugins/jdbc
# Copy all plugins from local ./plugins into the image
COPY plugins/jdbc /opt/kafka/plugins/jdbc

# Fix permissions so Kafka Connect can read plugins
RUN chown -R 1001:0 /opt/kafka/plugins && \
    chmod -R g+rwX /opt/kafka/plugins

# Switch back to non-root user (required by OpenShift)
USER 1001
