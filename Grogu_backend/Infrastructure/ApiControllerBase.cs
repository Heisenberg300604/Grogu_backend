using System;
using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;

namespace Grogu.Infrastructure
{
    /// <summary>
    /// Shared plumbing for the <c>/api/v1</c> controllers: the signed-in user id and
    /// the raw request body that gets forwarded to a stored function.
    /// </summary>
    public abstract class ApiControllerBase : ControllerBase
    {
        protected readonly GroguDb Db;

        protected ApiControllerBase(GroguDb db)
        {
            Db = db;
        }

        /// <summary>
        /// The caller's user id taken from the bearer token, or null when anonymous.
        /// Never read from the request body: a client must not be able to act as
        /// someone else by naming them.
        /// </summary>
        protected int? CurrentUserId
        {
            get
            {
                var claim = User?.FindFirst(ClaimTypes.NameIdentifier)
                            ?? User?.FindFirst("sub");

                int id;
                if (claim != null && int.TryParse(claim.Value, out id))
                {
                    return id;
                }

                return null;
            }
        }

        /// <summary>
        /// The request body as JSON text. <see cref="System.Text.Json.JsonElement"/>
        /// is used instead of a typed DTO because the stored functions own the
        /// contract and validate it; adding DTOs here would restate the frontend's
        /// types a third time and let them drift.
        /// </summary>
        protected static string BodyJson(System.Text.Json.JsonElement body)
        {
            return body.ValueKind == System.Text.Json.JsonValueKind.Undefined
                ? "{}"
                : body.GetRawText();
        }
    }
}
