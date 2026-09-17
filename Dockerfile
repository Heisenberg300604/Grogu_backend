FROM mcr.microsoft.com/dotnet/sdk:5.0 AS build

WORKDIR /src

COPY ["Grogu_backend/Grogu_backend.csproj", "Grogu_backend/"]
RUN dotnet restore "Grogu_backend/Grogu_backend.csproj"

COPY . .
WORKDIR "/src/Grogu_backend"
RUN dotnet build "Grogu_backend.csproj" -c Release -o /app/build --no-restore
RUN dotnet publish "Grogu_backend.csproj" -c Release -o /app/publish /p:UseAppHost=false --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:5.0 AS final

WORKDIR /app
ENV ASPNETCORE_URLS=http://+:80
EXPOSE 80

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "Grogu_backend.dll"]