using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using System;
using System.Data;
using Npgsql;

namespace Grogu.Controllers
{
    [Route("api/users")]
    [ApiController]
    public class UserController : ControllerBase
    {
        private readonly IConfiguration _configuration;
        private readonly string conn;

        public UserController(IConfiguration configuration)
        {
            _configuration = configuration;
            conn = _configuration.GetConnectionString("NeonDBConnection") ?? "Server=placeholder;Database=grogu;Uid=user;Pwd=password;";
        }

        [HttpGet("{id}")]
        public IActionResult GetUserById(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM user_get_by_id(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                var user = new
                                {
                                    id = reader.GetInt32(reader.GetOrdinal("id")),
                                    email = reader["email"]?.ToString(),
                                    role = reader["role"]?.ToString(),
                                    created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                                };
                                return Ok(user);
                            }
                        }
                    }
                    return NotFound(new { Message = "User not found." });
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpPut("{id}")]
        public IActionResult UpdateUser(int id, [FromForm] string email, [FromForm] string role)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT user_update(@Id, @Email, @Role)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);
                        cmd.Parameters.AddWithValue("@Email", string.IsNullOrEmpty(email) ? DBNull.Value : (object)email);
                        cmd.Parameters.AddWithValue("@Role", string.IsNullOrEmpty(role) ? DBNull.Value : (object)role);

                        var updated = (bool)(cmd.ExecuteScalar() ?? false);

                        if (!updated)
                        {
                            return NotFound(new { Message = "User not found." });
                        }

                        return Ok(new { Message = "User updated successfully." });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpDelete("{id}")]
        public IActionResult DeleteUser(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT user_delete(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        var deleted = (bool)(cmd.ExecuteScalar() ?? false);

                        if (!deleted)
                        {
                            return NotFound(new { Message = "User not found." });
                        }

                        return Ok(new { Message = "User deleted successfully." });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }
    }
}