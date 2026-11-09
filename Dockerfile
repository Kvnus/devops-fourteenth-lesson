FROM maven:3.9 AS builder

WORKDIR /build
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q clean package -DskipTests

FROM alpine:3.20

RUN apk add --no-cache \
        openjdk21-jre-headless \
        gcompat

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /build/target/demo.jar app.jar

RUN chown -R app:app /app
USER app

EXPOSE 8080

ENTRYPOINT ["java", \
            "-XX:MaxRAMPercentage=75.0", \
            "-Djava.security.egd=file:/dev/./urandom", \
            "-jar", "/app/app.jar"]