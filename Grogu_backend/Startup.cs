using System;
using System.Linq;
using Grogu.Infrastructure;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.OpenApi.Models;

namespace Grogu_backend
{
    public class Startup
    {
        public Startup(IConfiguration configuration, IWebHostEnvironment environment)
        {
            Configuration = configuration;
            Environment = environment;
        }

        public IConfiguration Configuration { get; }
        public IWebHostEnvironment Environment { get; }

        public void ConfigureServices(IServiceCollection services)
        {
            services.AddControllers();

            services.AddSwaggerGen(c =>
            {
                c.SwaggerDoc("v1", new OpenApiInfo { Title = "Grogu_backend", Version = "v1" });
            });

            services.AddSingleton<GroguDb>();

            // Constructed eagerly so a missing or too-short Jwt__Key fails at
            // startup rather than on the first login attempt.
            var jwt = new JwtTokenService(Configuration, Environment.IsDevelopment());
            services.AddSingleton(jwt);

            services
                .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
                .AddJwtBearer(options =>
                {
                    options.TokenValidationParameters = jwt.ValidationParameters;
                    options.RequireHttpsMetadata = !Environment.IsDevelopment();
                });

            services.AddCors(options =>
            {
                options.AddPolicy("FrontendPolicy", policy =>
                {
                    policy.WithOrigins(AllowedOrigins())
                        .AllowAnyHeader()
                        .AllowAnyMethod();
                });
            });
        }

        /// <summary>
        /// Browser origins allowed to call the API. Configured through
        /// <c>Cors__AllowedOrigins__0</c>, <c>Cors__AllowedOrigins__1</c>, ... so a
        /// new deployment does not need a code change; the local dev servers are
        /// always permitted.
        /// </summary>
        private string[] AllowedOrigins()
        {
            var configured = Configuration
                .GetSection("Cors:AllowedOrigins")
                .Get<string[]>() ?? new string[0];

            var defaults = new[]
            {
                "http://localhost:3000",
                "http://localhost:3001"
            };

            return configured
                .Concat(defaults)
                .Where(origin => !string.IsNullOrWhiteSpace(origin))
                .Select(origin => origin.TrimEnd('/'))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }

        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
                app.UseHttpsRedirection();
            }

            // Swagger is served in every environment: the frontend team needs the
            // deployed contract, and it exposes no data on its own.
            app.UseSwagger();
            app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "Grogu_backend v1"));

            app.UseRouting();

            app.UseCors("FrontendPolicy");

            app.UseAuthentication();
            app.UseAuthorization();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapControllers();
            });
        }
    }
}
