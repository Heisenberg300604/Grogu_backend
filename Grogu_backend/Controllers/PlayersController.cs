using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using System;
using System.Data;
using Npgsql;
using System.Collections.Generic;

namespace Grogu.Controllers
{
    // Player onboarding, profile management, and playtest applications
    [Route("api/players")]
    [ApiController]
    public class PlayerController : ControllerBase
    {
        private readonly IConfiguration _configuration;
        private readonly string conn;

        public PlayerController(IConfiguration configuration)
        {
            _configuration = configuration;
            conn = _configuration.GetConnectionString("GroguConnectionString") ?? _configuration.GetConnectionString("NeonDBConnection") ?? "Server=placeholder;Database=grogu;Uid=user;Pwd=password;";
        }

        [HttpGet("{id}")]       //get the player info, use player id
        public IActionResult GetPlayerProfile(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM player_get(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                var player = new
                                {
                                    id = reader.GetInt32(reader.GetOrdinal("id")),
                                    user_id = reader.GetInt32(reader.GetOrdinal("user_id")),
                                    age = reader["age"] != DBNull.Value ? reader.GetInt32(reader.GetOrdinal("age")) : (int?)null,
                                    experience = reader["experience"] != DBNull.Value ? reader["experience"].ToString() : null,
                                    platforms = reader["platforms"] != DBNull.Value ? reader["platforms"].ToString() : null,
                                    genres = reader["genres"] != DBNull.Value ? reader["genres"].ToString() : null,
                                    created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                                };
                                return Ok(player);
                            }
                        }
                    }
                    return NotFound(new { Message = "Player profile not found." });
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpPost("saveProfile")]       // if the user id doesn't exists, player cannot be added, use user id
        public IActionResult SavePlayerProfile([FromForm] int userId, [FromForm] int age, [FromForm] string experience, [FromForm] string platforms, [FromForm] string genres)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT player_save(@UserId, @Age, @Experience, @Platforms, @Genres)", con))
                    {
                        cmd.Parameters.AddWithValue("@UserId", userId);
                        cmd.Parameters.AddWithValue("@Age", age);
                        cmd.Parameters.AddWithValue("@Experience", experience ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@Platforms", platforms ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@Genres", genres ?? (object)DBNull.Value);

                        var playerId = cmd.ExecuteScalar();
                        return StatusCode(201, new { Message = "Player profile saved successfully.", PlayerId = playerId });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpPost("playersApplyPlaytest")]      // apply for playtest, use player id and playtest id
        public IActionResult ApplyToPlaytest([FromForm] int playerId, [FromForm] int playtestId)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT player_apply_playtest(@PlayerId, @PlaytestId)", con))
                    {
                        cmd.Parameters.AddWithValue("@PlayerId", playerId);
                        cmd.Parameters.AddWithValue("@PlaytestId", playtestId);

                        var appId = cmd.ExecuteScalar();
                        return StatusCode(201, new { Message = "Applied to playtest successfully.", ApplicationId = appId });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpPut("{id}")]       //user player id for update
        public IActionResult UpdatePlayerProfile(int id, [FromForm] int? age, [FromForm] string experience, [FromForm] string platforms, [FromForm] string genres)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT player_update(@Id, @Age, @Experience, @Platforms, @Genres)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);
                        cmd.Parameters.AddWithValue("@Age", (object)age ?? DBNull.Value);
                        cmd.Parameters.AddWithValue("@Experience", string.IsNullOrEmpty(experience) ? DBNull.Value : (object)experience);
                        cmd.Parameters.AddWithValue("@Platforms", string.IsNullOrEmpty(platforms) ? DBNull.Value : (object)platforms);
                        cmd.Parameters.AddWithValue("@Genres", string.IsNullOrEmpty(genres) ? DBNull.Value : (object)genres);

                        var updated = (bool)(cmd.ExecuteScalar() ?? false);

                        if (!updated)
                        {
                            return NotFound(new { Message = "Player profile not found." });
                        }

                        return Ok(new { Message = "Player profile updated successfully." });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpDelete("{id}")]        // delete using player id
        public IActionResult DeletePlayer(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT player_delete(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        var deleted = (bool)(cmd.ExecuteScalar() ?? false);

                        if (!deleted)
                        {
                            return NotFound(new { Message = "Player record not found." });
                        }

                        return Ok(new { Message = "Player record deleted successfully." });
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