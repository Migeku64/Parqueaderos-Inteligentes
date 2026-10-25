FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY . .
ENV NODE_ENV=production
EXPOSE 3000
# Crea las tablas (si no existen), carga datos de demostración solo si la base está vacía y arranca
CMD ["sh", "-c", "node scripts/migrate.js && node scripts/seed.js && node src/server.js"]
