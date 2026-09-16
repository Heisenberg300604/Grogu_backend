using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using System;
using System.Data;
using Npgsql;

namespace Grogu.Controllers
{
    [Route("api/applications")]
    [ApiController]
    public class ApplicationController : ControllerBase
    {
        private readonly IConfiguration _configuration;
        private readonly string conn;

        public ApplicationController(IConfiguration configuration)
        {
            _configuration = configuration;
            conn = _configuration.GetConnectionString("NeonDBConnection") ?? "Server=placeholder;Database=grogu;Uid=user;Pwd=password;";
        }

        [HttpGet("{id}")]
        public IActionResult GetApplicationById(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM application_get(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                var application = new
                                {
                                    id = reader.GetInt32(reader.GetOrdinal("id")),
                                    player_id = reader.GetInt32(reader.GetOrdinal("player_id")),
                                    playtest_id = reader.GetInt32(reader.GetOrdinal("playtest_id")),
                                    status = reader["status"]?.ToString(),
                                    created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                                };
                                return Ok(application);
                            }
                        }
                    }
                    return NotFound(new { Message = "Application not found." });
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpPut("{id}/status")]
        public IActionResult UpdateApplicationStatus(int id, [FromForm] string status)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT application_status_update(@Id, @Status)", con))
                    {                   // COMPLETED, PENDING
                        cmd.Parameters.AddWithValue("@Id", id);
                        cmd.Parameters.AddWithValue("@Status", string.IsNullOrEmpty(status) ? DBNull.Value : (object)status);

                        var updated = (bool)(cmd.ExecuteScalar() ?? false);

                        if (!updated)
                        {
                            return NotFound(new { Message = "Application not found." });
                        }

                        return Ok(new { Message = "Application status updated successfully." });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpDelete("{id}")]
        public IActionResult DeleteApplication(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT application_delete(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        var deleted = (bool)(cmd.ExecuteScalar() ?? false);

                        if (!deleted)
                        {
                            return NotFound(new { Message = "Application not found." });
                        }

                        return Ok(new { Message = "Application deleted successfully." });
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