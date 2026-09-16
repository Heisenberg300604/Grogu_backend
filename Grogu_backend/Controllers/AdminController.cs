using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using System;
using System.Data;
using Npgsql;
using System.Collections.Generic;

namespace Grogu.Controllers
{
    [Route("api/admin")]
    [ApiController]
    public class AdminController : ControllerBase
    {
        private readonly IConfiguration _configuration;
        private readonly string conn;

        public AdminController(IConfiguration configuration)
        {
            _configuration = configuration;
            conn = _configuration.GetConnectionString("GroguConnectionString") ?? _configuration.GetConnectionString("NeonDBConnection") ?? "Server=placeholder;Database=grogu;Uid=user;Pwd=password;";
        }

        [HttpGet("stats")]      //GET NUMBER OF ALL PLAYERS, USERS, APPLICATIONS, ETC
        public IActionResult GetAdminStats()
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM admin_stats_get()", con);

                    using (NpgsqlDataReader reader = cmd.ExecuteReader())
                    {
                        if (reader.Read())
                        {
                            var stats = new
                            {
                                total_users = reader.GetInt64(reader.GetOrdinal("total_users")),
                                total_players = reader.GetInt64(reader.GetOrdinal("total_players")),
                                total_studios = reader.GetInt64(reader.GetOrdinal("total_studios")),
                                total_playtests = reader.GetInt64(reader.GetOrdinal("total_playtests")),
                                total_applications = reader.GetInt64(reader.GetOrdinal("total_applications")),
                                total_feedback = reader.GetInt64(reader.GetOrdinal("total_feedback"))
                            };
                            return Ok(stats);
                        }
                    }
                    return NotFound(new { Message = "Stats not found." });
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpGet("users")]      //GET ALL USERS
        public IActionResult GetAllUsers()
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                var usersList = new List<object>();
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM admin_get_users()", con);

                    using (NpgsqlDataReader reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            usersList.Add(new
                            {
                                id = reader.GetInt32(reader.GetOrdinal("id")),
                                email = reader["email"] != DBNull.Value ? reader["email"].ToString() : null,
                                role = reader["role"] != DBNull.Value ? reader["role"].ToString() : null,
                                created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                            });
                        }
                    }
                    return Ok(usersList);
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpGet("playtests")]      //GET ALL PLAYTESTS
        public IActionResult GetAllPlaytests()
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                var playtestsList = new List<object>();
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM admin_get_playtests()", con);

                    using (NpgsqlDataReader reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            playtestsList.Add(new
                            {
                                id = reader.GetInt32(reader.GetOrdinal("id")),
                                studio_id = reader.GetInt32(reader.GetOrdinal("studio_id")),
                                game_name = reader["game_name"] != DBNull.Value ? reader["game_name"].ToString() : null,
                                genre = reader["genre"] != DBNull.Value ? reader["genre"].ToString() : null,
                                platform = reader["platform"] != DBNull.Value ? reader["platform"].ToString() : null,
                                requirements = reader["requirements"] != DBNull.Value ? reader["requirements"].ToString() : null,
                                target_players = reader["target_players"] != DBNull.Value ? reader.GetInt32(reader.GetOrdinal("target_players")) : (int?)null,
                                created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                            });
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

        [HttpGet("logs")]       //admin activity history
        public IActionResult GetAdminLogs()
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                var logsList = new List<object>();
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM admin_logs_get()", con);

                    using (NpgsqlDataReader reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            logsList.Add(new
                            {
                                id = reader.GetInt32(reader.GetOrdinal("id")),
                                admin_user_id = reader.GetInt32(reader.GetOrdinal("admin_user_id")),
                                action = reader["action"] != DBNull.Value ? reader["action"].ToString() : null,
                                target_entity = reader["target_entity"] != DBNull.Value ? reader["target_entity"].ToString() : null,
                                target_id = reader["target_id"] != DBNull.Value ? reader.GetInt32(reader.GetOrdinal("target_id")) : (int?)null,
                                created_at = reader["created_at"] != DBNull.Value ? reader.GetDateTime(reader.GetOrdinal("created_at")).ToString("yyyy-MM-dd HH:mm:ss") : null
                            });
                        }
                    }
                    return Ok(logsList);
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }

        [HttpDelete("users/{id}")]      //DELETE
        public IActionResult DeleteUser(int id)
        {
            using (NpgsqlConnection con = new NpgsqlConnection(conn))
            {
                try
                {
                    if (con.State != ConnectionState.Open) { con.Open(); }
                    NpgsqlCommand cmd = new NpgsqlCommand("SELECT admin_delete_user(@Id)", con);
                    cmd.Parameters.AddWithValue("@Id", id);

                    var deleted = (bool)(cmd.ExecuteScalar() ?? false);

                    if (!deleted)
                    {
                        return NotFound(new { Message = "User record not found." });
                    }

                    return Ok(new { Message = "User record deleted successfully." });
                }
                catch (Exception ex)
                {
                    return StatusCode(500, new { Message = ex.Message });
                }
            }
        }
    }
}