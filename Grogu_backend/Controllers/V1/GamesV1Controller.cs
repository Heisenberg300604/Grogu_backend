using System.Text.Json;
using System.Threading.Tasks;
using Grogu.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Grogu.Controllers.V1
{
    /// <summary>
    /// Developer-owned games, for the frontend's <c>lib/services/games.ts</c>.
    ///
    /// Entirely new: the old schema inlined a <c>game_name</c> on each playtest, so
    /// a game was not something a developer could own, list or edit.
    /// </summary>
    [ApiController]
    [Route("api/v1/games")]
    [Authorize]
    public class GamesV1Controller : ApiControllerBase
    {
        public GamesV1Controller(GroguDb db) : base(db) { }

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body)
        {
            return Db.JsonAsync(
                "SELECT grogu_game_save(@UserId, NULL, @Input)",
                GroguDb.Int("@UserId", CurrentUserId),
                GroguDb.Json("@Input", BodyJson(body)));
        }

        [HttpPatch("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body)
        {
            return Db.JsonAsync(
                "SELECT grogu_game_save(@UserId, @GameId, @Input)",
                GroguDb.Int("@UserId", CurrentUserId),
                GroguDb.Int("@GameId", id),
                GroguDb.Json("@Input", BodyJson(body)));
        }
    }
}
