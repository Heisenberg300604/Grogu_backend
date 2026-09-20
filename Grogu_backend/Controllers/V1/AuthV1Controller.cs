using System;
using System.Text.Json;
using System.Threading.Tasks;
using Grogu.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Grogu.Controllers.V1
{
    /// <summary>
    /// Sign-up, sign-in and session for the frontend's <c>lib/services/auth.ts</c>.
    ///
    /// Replaces <c>/api/auth</c>, which took form fields, compared passwords in
    /// plaintext and issued no credential at all. Responses carry a bearer token
    /// plus the <c>User</c> the frontend's <c>Session</c> is built from.
    /// </summary>
    [ApiController]
    [Route("api/v1/auth")]
    public class AuthV1Controller : ApiControllerBase
    {
        private readonly JwtTokenService _jwt;

        public AuthV1Controller(GroguDb db, JwtTokenService jwt) : base(db)
        {
            _jwt = jwt;
        }

        [HttpPost("signup")]
        [AllowAnonymous]
        public async Task<IActionResult> Signup([FromBody] JsonElement body)
        {
            var result = await Db.QueryJsonAsync(
                "SELECT grogu_signup(@Input)",
                GroguDb.Json("@Input", BodyJson(body)));

            return result.Error ?? SessionResponse(result.Json, 201);
        }

        [HttpPost("login")]
        [AllowAnonymous]
        public async Task<IActionResult> Login([FromBody] JsonElement body)
        {
            string email = null;
            string password = null;

            JsonElement value;
            if (body.ValueKind == JsonValueKind.Object)
            {
                if (body.TryGetProperty("email", out value) && value.ValueKind == JsonValueKind.String)
                {
                    email = value.GetString();
                }
                if (body.TryGetProperty("password", out value) && value.ValueKind == JsonValueKind.String)
                {
                    password = value.GetString();
                }
            }

            if (string.IsNullOrWhiteSpace(email) || string.IsNullOrEmpty(password))
            {
                return GroguDb.Error(400, "validation", "Enter your email and password.");
            }

            var result = await Db.QueryJsonAsync(
                "SELECT grogu_login(@Email, @Password)",
                GroguDb.Text("@Email", email),
                GroguDb.Text("@Password", password));

            return result.Error ?? SessionResponse(result.Json, 200);
        }

        /// <summary>
        /// Re-reads the caller's own user record. The frontend calls this on load to
        /// find out whether a stored token is still valid.
        /// </summary>
        [HttpGet("session")]
        [Authorize]
        public async Task<IActionResult> Session()
        {
            var userId = CurrentUserId;
            if (userId == null)
            {
                return GroguDb.Error(401, "invalid-credentials", "Not signed in.");
            }

            return await Db.JsonAsync(
                "SELECT grogu_bootstrap(@UserId) -> 'session'",
                GroguDb.Int("@UserId", userId));
        }

        /// <summary>
        /// Tokens are stateless and self-expiring, so there is nothing to revoke
        /// server-side; the frontend discards its copy. The endpoint exists so the
        /// client has one call to make and a place to hang revocation later.
        /// </summary>
        [HttpPost("logout")]
        [AllowAnonymous]
        public IActionResult Logout()
        {
            return Ok(new { message = "Signed out." });
        }

        /// <summary>Wraps a user document from the database in a signed session.</summary>
        private IActionResult SessionResponse(string userJson, int statusCode)
        {
            using (var document = JsonDocument.Parse(userJson))
            {
                var user = document.RootElement;

                int userId;
                if (!int.TryParse(user.GetProperty("id").GetString(), out userId))
                {
                    return GroguDb.Error(500, "server-error", "Could not establish a session.");
                }

                var role = user.GetProperty("role").GetString();

                DateTime expiresAt;
                var token = _jwt.Issue(userId, role, out expiresAt);

                return new ObjectResult(new
                {
                    token,
                    expiresAt = expiresAt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"),
                    user = JsonSerializer.Deserialize<JsonElement>(userJson),
                    role
                })
                { StatusCode = statusCode };
            }
        }
    }
}
