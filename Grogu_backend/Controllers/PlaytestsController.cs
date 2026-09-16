using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using System;
using System.Data;
using Npgsql;
using System.Collections.Generic;

namespace Grogu.Controllers
{
    [Route("api/playtests")]
    [ApiController]
    public class PlaytestController : ControllerBase
    {
        private readonly IConfiguration _configuration;
        private readonly string conn;

        public PlaytestController(IConfiguration configuration)
        {
            _configuration = configuration;
            conn = _configuration.GetConnectionString("NeonDBConnection") ?? "Server=placeholder;Database=grogu;Uid=user;Pwd=password;";
        }

        [HttpPost]          // use studio id
        public IActionResult CreatePlaytest([FromForm] int studioId, [FromForm] string gameName, [FromForm] string genre, [FromForm] string platform, [FromForm] string requirements, [FromForm] int? targetPlayers)
        {
            if (string.IsNullOrEmpty(gameName) || string.IsNullOrEmpty(genre) || string.IsNullOrEmpty(platform))
            {
                return BadRequest(new { Message = "Game name, genre, and platform are required." });
            }

            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {                   
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT playtest_create(@StudioId, @GameName, @Genre, @Platform, @Requirements, @TargetPlayers)", con))
                    {
                        cmd.Parameters.AddWithValue("@StudioId", studioId);
                        cmd.Parameters.AddWithValue("@GameName", gameName);
                        cmd.Parameters.AddWithValue("@Genre", genre);
                        cmd.Parameters.AddWithValue("@Platform", platform);
                        cmd.Parameters.AddWithValue("@Requirements", string.IsNullOrEmpty(requirements) ? DBNull.Value : (object)requirements);
                        cmd.Parameters.AddWithValue("@TargetPlayers", (object)targetPlayers ?? DBNull.Value);

                        var playtestId = cmd.ExecuteScalar();
                        return StatusCode(201, new { Message = "Playtest created successfully.", PlaytestId = playtestId });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpGet("{id}")]       //use playtest id
        public IActionResult GetPlaytestById(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM playtest_get(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                var playtest = new
                                {
                                    id = reader.GetInt32(reader.GetOrdinal("id")),
                                    studio_id = reader.GetInt32(reader.GetOrdinal("studio_id")),
                                    game_name = reader["game_name"]?.ToString(),
                                    genre = reader["genre"]?.ToString(),
                                    platform = reader["platform"]?.ToString(),
                                    requirements = reader["requirements"]?.ToString(),
                                    target_players = reader["target_players"] != DBNull.Value ? reader.GetInt32(reader.GetOrdinal("target_players")) : (int?)null,
                                    created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                                };
                                return Ok(playtest);
                            }
                        }
                    }
                    return NotFound(new { Message = "Playtest not found." });
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpGet("{id}/applications")]      // use playtest id
        public IActionResult GetPlaytestApplications(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                var applicationsList = new List<object>();
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM playtest_applications(@PlaytestId)", con))
                    {
                        cmd.Parameters.AddWithValue("@PlaytestId", id);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            while (reader.Read())
                            {
                                applicationsList.Add(new
                                {
                                    application_id = reader.GetInt32(reader.GetOrdinal("application_id")),
                                    player_id = reader.GetInt32(reader.GetOrdinal("player_id")),
                                    user_id = reader.GetInt32(reader.GetOrdinal("user_id")),
                                    email = reader["email"]?.ToString(),
                                    age = reader["age"] != DBNull.Value ? reader.GetInt32(reader.GetOrdinal("age")) : (int?)null,
                                    experience = reader["experience"]?.ToString(),
                                    platforms = reader["platforms"]?.ToString(),
                                    genres = reader["genres"]?.ToString(),
                                    status = reader["status"]?.ToString(),
                                    applied_at = reader["applied_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("applied_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                                });
                            }
                        }
                    }
                    return Ok(applicationsList);
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }
    }
}