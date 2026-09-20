using System.Text.Json;
using System.Threading.Tasks;
using Grogu.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Grogu.Controllers.V1
{
    /// <summary>
    /// Acting on an existing application, for the frontend's
    /// <c>lib/services/applications.ts</c>.
    ///
    /// The legacy <c>PUT /api/applications/{id}/status</c> let any caller set any
    /// status on any application. Withdrawing is now restricted to the tester who
    /// applied, and deciding to the developer who owns the playtest.
    /// </summary>
    [ApiController]
    [Route("api/v1/applications")]
    [Authorize]
    public class ApplicationsV1Controller : ApiControllerBase
    {
        public ApplicationsV1Controller(GroguDb db) : base(db) { }

        [HttpPost("{id:int}/withdraw")]
        public Task<IActionResult> Withdraw(int id)
        {
            return Db.JsonAsync(
                "SELECT grogu_application_withdraw(@UserId, @ApplicationId)",
                GroguDb.Int("@UserId", CurrentUserId),
                GroguDb.Int("@ApplicationId", id));
        }

        [HttpPost("{id:int}/decision")]
        public Task<IActionResult> Decide(int id, [FromBody] JsonElement body)
        {
            string decision = null;
            string note = null;

            JsonElement value;
            if (body.ValueKind == JsonValueKind.Object)
            {
                if (body.TryGetProperty("decision", out value) && value.ValueKind == JsonValueKind.String)
                {
                    decision = value.GetString();
                }
                if (body.TryGetProperty("note", out value) && value.ValueKind == JsonValueKind.String)
                {
                    note = value.GetString();
                }
            }

            if (string.IsNullOrWhiteSpace(decision))
            {
                return Task.FromResult(GroguDb.Error(400, "validation", "A decision is required."));
            }

            return Db.JsonAsync(
                "SELECT grogu_application_decide(@UserId, @ApplicationId, @Decision, @Note)",
                GroguDb.Int("@UserId", CurrentUserId),
                GroguDb.Int("@ApplicationId", id),
                GroguDb.Text("@Decision", decision),
                GroguDb.Text("@Note", note));
        }
    }
}
