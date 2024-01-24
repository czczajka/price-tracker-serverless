mkdir -p dist/handler
mkdir -p dist/gateway

# Ugly hack but go embed works in a little strange way
cp app.config cmd/gateway/app.config
cp app.config cmd/handler/app.config

docker build -t mygoapp .

docker create --name temp-container mygoapp
docker cp temp-container:/root/handler.zip ./dist/handler/main.zip
docker cp temp-container:/root/gateway.zip ./dist/gateway/main.zip
docker rm temp-container