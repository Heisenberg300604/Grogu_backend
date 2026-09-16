using Microsoft.AspNetCore.Mvc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Grogu_backend.Controllers
{
    public class MatchScoresController : Controller
    {
        public IActionResult Index()
        {
            return View();
        }
    }
}
