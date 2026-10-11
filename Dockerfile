FROM eclipse-temurin:17-jre

RUN useradd --system --uid 10001 --no-create-home app
WORKDIR /app
COPY --chown=app app.jar app.jar
USER app

# Cloud Run injects PORT; -Dserver.port makes Spring Boot apps listen on it.
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "exec java -XX:MaxRAMPercentage=75 -Dserver.port=${PORT} -jar /app/app.jar"]
