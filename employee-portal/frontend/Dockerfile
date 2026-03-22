FROM nginx:alpine

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy frontend HTML
COPY index.html /usr/share/nginx/html/

# Create custom error page
RUN echo '<html><body><h1>Service Temporarily Unavailable</h1><p>The backend service is starting up. Please try again in a moment.</p></body></html>' > /usr/share/nginx/html/50x.html

EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/health || exit 1

# Run nginx
CMD ["nginx", "-g", "daemon off;"]