using System.Text.Json;
using System.Threading.Tasks;
using Grogu.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Grogu.Controllers.V1
{
    /// <summary>
    /// The tester workspace — download the build, tick tasks off, submit feedback —
    /// for the frontend's <c>lib/services/tests.ts</c>.
    ///
    /// None of this existed before: the old backend could record a single 1-5
    /// rating with a comment and had nowhere to keep a tester's progress.
    /// Every call requires the caller to be on the playtest's accepted roster.
    /// </summary>
    [ApiController]
    [Route("api/v1/tests")]
    [Authorize]
    public class TestsV1Controller : ApiControllerBase
    {
        public TestsV1Controller(GroguDb db) : base(db) { }

        [HttpPost("{playtestId:int}/download")]
        public Task<IActionResult> Download(int playtestId)
        {
            return Db.JsonAsync(
                "SELECT grogu_test_download(@UserId, @PlaytestId)",
                GroguDb.Int("@UserId", CurrentUserId),
                GroguDb.Int("@PlaytestId", playtestId));
        }

        [HttpPost("{playtestId:int}/tasks/{taskId:int}/toggle")]
        public Task<IActionResult> ToggleTask(int playtestId, int taskId)
        {
            return Db.JsonAsync(
                "SELECT grogu_test_toggle_task(@UserId, @PlaytestId, @TaskId)",
                GroguDb.Int("@UserId", CurrentUserId),
                GroguDb.Int("@PlaytestId", playtestId),
                GroguDb.Int("@TaskId", taskId));
        }

        /// <summary>Returns both the new feedback and the updated progress row.</summary>
        [HttpPost("{playtestId:int}/feedback")]
        public Task<IActionResult> SubmitFeedback(int playtestId, [FromBody] JsonElement body)
        {
            return Db.JsonAsync(
                "SELECT grogu_feedback_submit(@UserId, @PlaytestId, @Input)",
                GroguDb.Int("@UserId", CurrentUserId),
                GroguDb.Int("@PlaytestId", playtestId),
                GroguDb.Json("@Input", BodyJson(body)));
        }
    }
}
