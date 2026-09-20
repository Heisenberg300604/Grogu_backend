using System.Threading.Tasks;
using Grogu.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Grogu.Controllers.V1
{
    /// <summary>
    /// Read state for the notification menu, for the frontend's
    /// <c>lib/services/notifications.ts</c>. New; the old backend raised no
    /// notifications at all.
    /// </summary>
    [ApiController]
    [Route("api/v1/notifications")]
    [Authorize]
    public class NotificationsV1Controller : ApiControllerBase
    {
        public NotificationsV1Controller(GroguDb db) : base(db) { }

        [HttpPost("{id:int}/read")]
        public Task<IActionResult> MarkRead(int id)
        {
            return Db.JsonAsync(
                "SELECT grogu_notification_read(@UserId, @NotificationId)",
                GroguDb.Int("@UserId", CurrentUserId),
                GroguDb.Int("@NotificationId", id));
        }

        /// <summary>
        /// The frontend passes a user id here; it is ignored in favour of the token,
        /// so one user can never clear another's notifications.
        /// </summary>
        [HttpPost("read-all")]
        public Task<IActionResult> MarkAllRead()
        {
            return Db.JsonAsync(
                "SELECT grogu_notification_read_all(@UserId)",
                GroguDb.Int("@UserId", CurrentUserId));
        }
    }
}
