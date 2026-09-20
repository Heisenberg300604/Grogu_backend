using System.Threading.Tasks;
using Grogu.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Grogu.Controllers.V1
{
    /// <summary>
    /// The whole dataset the frontend store holds, in one document.
    ///
    /// The client does its joins and aggregations locally across collections —
    /// roughly thirty selector hooks in <c>lib/hooks/use-grogu.ts</c> read
    /// <c>games</c>, <c>playtests</c>, <c>applications</c>, <c>feedback</c> and
    /// <c>testProgress</c> together — so serving them as one snapshot lets that
    /// code keep working against real data instead of a seeded local store.
    ///
    /// The payload is scoped to the caller by <c>grogu_bootstrap</c>: private
    /// collections only ever contain rows that belong to them or to their own
    /// playtests, and other people's email addresses are blanked. Anonymous
    /// callers get the public view the marketing and discover pages need.
    /// </summary>
    [ApiController]
    [Route("api/v1/bootstrap")]
    public class BootstrapV1Controller : ApiControllerBase
    {
        public BootstrapV1Controller(GroguDb db) : base(db) { }

        [HttpGet]
        [AllowAnonymous]
        public Task<IActionResult> Get()
        {
            return Db.JsonAsync(
                "SELECT grogu_bootstrap(@UserId)",
                GroguDb.Int("@UserId", CurrentUserId));
        }
    }
}
