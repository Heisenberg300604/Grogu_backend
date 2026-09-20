using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;

namespace Grogu.Infrastructure
{
    /// <summary>
    /// Issues the bearer tokens the frontend sends on every authenticated call.
    ///
    /// The signing key comes from configuration (<c>Jwt__Key</c> in the
    /// environment) and is never compiled in. Outside Development a missing key
    /// is fatal at startup rather than silently falling back to something
    /// predictable.
    /// </summary>
    public class JwtTokenService
    {
        public const int ExpiryHours = 12;

        private readonly SymmetricSecurityKey _key;
        private readonly string _issuer;
        private readonly string _audience;

        public JwtTokenService(IConfiguration configuration, bool isDevelopment)
        {
            var configured = configuration["Jwt:Key"];

            if (string.IsNullOrWhiteSpace(configured))
            {
                if (!isDevelopment)
                {
                    throw new InvalidOperationException(
                        "No JWT signing key configured. Set the environment variable Jwt__Key " +
                        "to a random secret of at least 32 characters (see README).");
                }

                // Development convenience only: a fresh key each run, so tokens do
                // not survive a restart and no usable default ever ships.
                var random = new byte[48];
                using (var rng = System.Security.Cryptography.RandomNumberGenerator.Create())
                {
                    rng.GetBytes(random);
                }
                configured = Convert.ToBase64String(random);
            }
            else if (Encoding.UTF8.GetByteCount(configured) < 32)
            {
                throw new InvalidOperationException(
                    "Jwt__Key is too short. HMAC-SHA256 signing needs at least 32 bytes.");
            }

            _key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(configured));
            _issuer = configuration["Jwt:Issuer"] ?? "grogu-backend";
            _audience = configuration["Jwt:Audience"] ?? "grogu-frontend";
        }

        public TokenValidationParameters ValidationParameters
        {
            get
            {
                return new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = _issuer,
                    ValidateAudience = true,
                    ValidAudience = _audience,
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = _key,
                    ValidateLifetime = true,
                    ClockSkew = TimeSpan.FromMinutes(1)
                };
            }
        }

        /// <summary>Returns the signed token and the instant it expires.</summary>
        public string Issue(int userId, string role, out DateTime expiresAt)
        {
            expiresAt = DateTime.UtcNow.AddHours(ExpiryHours);

            var claims = new List<Claim>
            {
                new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                new Claim(ClaimTypes.Role, role ?? string.Empty)
            };

            var token = new JwtSecurityToken(
                issuer: _issuer,
                audience: _audience,
                claims: claims,
                notBefore: DateTime.UtcNow,
                expires: expiresAt,
                signingCredentials: new SigningCredentials(_key, SecurityAlgorithms.HmacSha256));

            return new JwtSecurityTokenHandler().WriteToken(token);
        }
    }
}
