using System.Text.Json;
using System.Threading.Tasks;
using Grogu.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Grogu.Controllers.V1
{
    /// <summary>
    /// The signed-in user's own profile, covering both the shared <c>User</c>
    /// fields and whichever role profile applies.
    /// </summary>
    [ApiController]
    [Route("api/v1/profile")]
    [Authorize]
    public class ProfileV1Controller : ApiControllerBase
    {
        public ProfileV1Controller(GroguDb db) : base(db) { }

        [HttpPatch]
        public Task<IActionResult> Save([FromBody] JsonElement body)
        {
            return Db.JsonAsync(
                "SELECT grogu_profile_save(@UserId, @Input)",
                GroguDb.Int("@UserId", CurrentUserId),
                GroguDb.Json("@Input", BodyJson(body)));
        }
    }
}
