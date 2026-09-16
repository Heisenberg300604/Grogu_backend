using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using System;
using System.Data;
using Npgsql;

namespace Grogu.Controllers
{
    [Route("api/auth")]
    [ApiController]
    public class AuthController : ControllerBase
    {
        private readonly IConfiguration _configuration;
        private readonly string conn;

        public AuthController(IConfiguration configuration)
        {
            _configuration = configuration;
            conn = _configuration.GetConnectionString("NeonDBConnection") ?? "Server=placeholder;Database=grogu;Uid=user;Pwd=password;";
        }

        [HttpPost("signup")]
        public IActionResult Signup([FromForm] string email, [FromForm] string role, [FromForm] string password)
        {
            if (string.IsNullOrEmpty(email) || string.IsNullOrEmpty(role) || string.IsNullOrEmpty(password))
            {
                return BadRequest(new { Message = "Email, role, and password are required." });
            }

            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT register_user(@Email, @Role, @Password)", con))
                    {
                        cmd.Parameters.AddWithValue("@Email", email);
                        cmd.Parameters.AddWithValue("@Role", role);
                        cmd.Parameters.AddWithValue("@Password", password);

                        var userId = cmd.ExecuteScalar();
                        return StatusCode(201, new { Message = "User registered successfully.", UserId = userId, Role = role });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpPost("login")]
        public IActionResult Login([FromForm] string email, [FromForm] string password)
        {
            if (string.IsNullOrEmpty(email) || string.IsNullOrEmpty(password))
            {
                return BadRequest(new { Message = "Email and password are required." });
            }

            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM verify_user_login(@Email, @Password)", con))
                    {
                        cmd.Parameters.AddWithValue("@Email", email);
                        cmd.Parameters.AddWithValue("@Password", password);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                var user = new
                                {
                                    id = reader.GetInt32(reader.GetOrdinal("id")),
                                    email = reader["email"].ToString(),
                                    role = reader["role"].ToString()
                                };
                                return Ok(new { Message = "Login successful.", User = user });
                            }
                        }
                    }
                    return Unauthorized(new { Message = "Invalid email or password." });
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }
    }
}