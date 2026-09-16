using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using System;
using System.Data;
using Npgsql;
using System.Collections.Generic;

namespace Grogu.Controllers
{
    [Route("api/studios")]
    [ApiController]
    public class StudiosController : ControllerBase
    {
        private readonly IConfiguration _configuration;
        private readonly string conn;

        public StudiosController(IConfiguration configuration)
        {
            _configuration = configuration;
            conn = _configuration.GetConnectionString("NeonDBConnection") ?? "Server=placeholder;Database=grogu;Uid=user;Pwd=password;";
        }

        [HttpGet("{id}")]
        public IActionResult GetStudioById(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM studio_get(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                var studio = new
                                {
                                    id = reader.GetInt32(reader.GetOrdinal("id")),
                                    user_id = reader.GetInt32(reader.GetOrdinal("user_id")),
                                    name = reader["name"]?.ToString(),
                                    website = reader["website"]?.ToString(),
                                    created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                                };
                                return Ok(studio);
                            }
                        }
                    }
                    return NotFound(new { Message = "Studio not found." });
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpPut("{id}")]
        public IActionResult UpdateStudio(int id, [FromForm] string name, [FromForm] string website)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT studio_update(@Id, @Name, @Website)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);
                        cmd.Parameters.AddWithValue("@Name", string.IsNullOrEmpty(name) ? DBNull.Value : (object)name);
                        cmd.Parameters.AddWithValue("@Website", string.IsNullOrEmpty(website) ? DBNull.Value : (object)website);

                        var updated = (bool)(cmd.ExecuteScalar() ?? false);

                        if (!updated)
                        {
                            return NotFound(new { Message = "Studio not found." });
                        }

                        return Ok(new { Message = "Studio profile updated successfully." });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpGet("{id}/playtests")]
        public IActionResult GetStudioPlaytests(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                var playtestsList = new List<object>();
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM studio_playtest(@StudioId)", con))
                    {
                        cmd.Parameters.AddWithValue("@StudioId", id);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            while (reader.Read())
                            {
                                playtestsList.Add(new
                                {
                                    id = reader.GetInt32(reader.GetOrdinal("id")),
                                    studio_id = reader.GetInt32(reader.GetOrdinal("studio_id")),
                                    game_name = reader["game_name"]?.ToString(),
                                    genre = reader["genre"]?.ToString(),
                                    platform = reader["platform"]?.ToString(),
                                    requirements = reader["requirements"]?.ToString(),
                                    target_players = reader["target_players"] != DBNull.Value ? reader.GetInt32(reader.GetOrdinal("target_players")) : (int?)null,
                                    created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                                });
                            }
                        }
                    }
                    return Ok(playtestsList);
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpDelete("{id}")]
        public IActionResult DeleteStudio(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT studio_delete(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        var deleted = (bool)(cmd.ExecuteScalar() ?? false);

                        if (!deleted)
                        {
                            return NotFound(new { Message = "Studio not found." });
                        }

                        return Ok(new { Message = "Studio deleted successfully." });
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