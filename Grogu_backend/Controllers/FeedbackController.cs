using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using System;
using System.Data;
using Npgsql;
using System.Collections.Generic;

namespace Grogu.Controllers
{
    [Route("api/feedback")]
    [ApiController]
    public class FeedbackController : ControllerBase
    {
        private readonly IConfiguration _configuration;
        private readonly string conn;

        public FeedbackController(IConfiguration configuration)
        {
            _configuration = configuration;
            conn = _configuration.GetConnectionString("NeonDBConnection") ?? "Server=placeholder;Database=grogu;Uid=user;Pwd=password;";
        }

        [HttpPost]
        public IActionResult SubmitFeedback([FromForm] int playtestId, [FromForm] int playerId, [FromForm] int rating, [FromForm] string comments)
        {
            if (rating < 1 || rating > 5)
            {
                return BadRequest(new { Message = "Rating must be between 1 and 5." });
            }

            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT feedback_submit(@PlaytestId, @PlayerId, @Rating, @Comments)", con))
                    {
                        cmd.Parameters.AddWithValue("@PlaytestId", playtestId);
                        cmd.Parameters.AddWithValue("@PlayerId", playerId);
                        cmd.Parameters.AddWithValue("@Rating", rating);
                        cmd.Parameters.AddWithValue("@Comments", string.IsNullOrEmpty(comments) ? DBNull.Value : (object)comments);

                        var feedbackId = cmd.ExecuteScalar();
                        return StatusCode(201, new { Message = "Feedback submitted successfully.", FeedbackId = feedbackId });
                    }
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpGet("{id}")]
        public IActionResult GetFeedbackById(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM feedback_get(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                var feedback = new
                                {
                                    id = reader.GetInt32(reader.GetOrdinal("id")),
                                    playtest_id = reader.GetInt32(reader.GetOrdinal("playtest_id")),
                                    player_id = reader.GetInt32(reader.GetOrdinal("player_id")),
                                    rating = reader.GetInt32(reader.GetOrdinal("rating")),
                                    comments = reader["comments"]?.ToString(),
                                    created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                                };
                                return Ok(feedback);
                            }
                        }
                    }
                    return NotFound(new { Message = "Feedback not found." });
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpGet("playtest/{playtestId}")]
        public IActionResult GetFeedbackByPlaytest(int playtestId)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                var feedbackList = new List<object>();
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM feedback_get_by_playtest(@PlaytestId)", con))
                    {
                        cmd.Parameters.AddWithValue("@PlaytestId", playtestId);

                        using (NpgsqlDataReader reader = cmd.ExecuteReader())
                        {
                            while (reader.Read())
                            {
                                feedbackList.Add(new
                                {
                                    id = reader.GetInt32(reader.GetOrdinal("id")),
                                    playtest_id = reader.GetInt32(reader.GetOrdinal("playtest_id")),
                                    player_id = reader.GetInt32(reader.GetOrdinal("player_id")),
                                    rating = reader.GetInt32(reader.GetOrdinal("rating")),
                                    comments = reader["comments"]?.ToString(),
                                    created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                                });
                            }
                        }
                    }
                    return Ok(feedbackList);
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpDelete("{id}")]
        public IActionResult DeleteFeedback(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT feedback_delete(@Id)", con))
                    {
                        cmd.Parameters.AddWithValue("@Id", id);

                        var deleted = (bool)(cmd.ExecuteScalar() ?? false);

                        if (!deleted)
                        {
                            return NotFound(new { Message = "Feedback not found." });
                        }

                        return Ok(new { Message = "Feedback deleted successfully." });
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