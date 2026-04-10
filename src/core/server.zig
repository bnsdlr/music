const std = @import("std");
const process = std.process;
const Io = std.Io;
const http = std.http;

const app = @import("../main.zig");
const lib = app.lib;

const log = std.log.scoped(.server);

pub fn run(init: process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const args = init.minimal.args;

    _ = args;
    // _ = gpa;

    var client: http.Client = .{ .allocator = gpa, .io = io };
    defer client.deinit();

    log.info("acoustid api key: {s}", .{app.config().acoustid_api_key});

    const result = try lib.acoustid.lookupByFingerprint(&client, gpa, .{ 
        .client = app.config().acoustid_api_key,
        // .duration = 187,
        // .fingerprint = "AQADtIlkJVIYJQmeo3mEZFbyYA_2LMctGY0aVTGqGyeSJzmJXCsDx_Hw4-fRo5mWB_1hRosOPwiVq4KOUMuO78Jk58bzgvE4oXF6XLzwfHDwZEN-KOZQ5AzRRcdz9CG2KjzC00pwIr-BMvFRafpx-ehzMJmUJ_iOHD0DLbGUg5R4onLyIB2ZBjdOUUafKAeZCz8eZEkzaEfOovmM6UcTrkadKMfj480RhmOg8dSQC-fR_EQfpfgOL5py5CSPN4fqGn4e5OtxHWHHwhHDQuP6I5yyuPB-XEqJWvGxb8clEi-PMB-0TYmO6MGPTjtKbUZuHOJxG9-FnLrw49YRvkSzB8p55Lh2sD2qzKBIRmiKzxKuOkfzRJKG6sQx5UXJ4Y5MbDmSHykZpThYacdE5kTjPMGXmbhjJPWDMA_6E4-a5BH6HU2PiykajulRWs6x50h6JUgrHuyaDx9N_IcVMtPxnciTmEh6_HgyB8cULhGJ6jweTkf4vFAdUpiuI_zRjKGE7wGX9DhK5si06IHOHemPPlyMWsWU49mPMzquo46iFOEP9ejzDeGVhvimwD9OEl9YPA_sIIceBfVbaOGSpTgplCPCfJlwSrOB7okkCT48Fn6OPsuRXB_y4-HxcMHR9EKf7MF55FkPTdKO96iFPUHz7EG4UHiOLzzy0Si0XMjjFZcogyl1eD8ePMfTHCHVvNBzIcyPiS1qEU1q5LKToOEuTMSlQNGDZtqhTsd56EN3HWmFE08d7AX1YKXx48-McwizBUIu6fjyBJUeNJoSBT9-5FEkB2WV1NDSIZeCNzOaJTq85-h7hNtGTTjOQ1zCBHVyPD90xugp4gl2gj9-KFeGK3xwSSg7HDsujU0CLdSFUkPO4BQP_3ii6Bm-44liFOlbSM-RH_OR_4FfJD16oS58SSjxfThPfBfCXAqSnRnuxEQTnUQZhWmEZ0dz9Frw6MiDo99x5DlRb8d4HE3GpWC-E7mS4xu2WMqPI6-kBi-u40rxIcwPzS_yDueJJjHxS2ieC88TPGlxSrB1nMczHc2kE9WifPgVNFuyFLUk9D_uJ6j-4KixbdmIsE-DkhlE56gcxcPbFH3RpPuQHwxJmMvx40lYxOpyiHJohIkuPMMzRcQs6UMfeM9wZRrCFyd0hi56xgfyXeiy5HhEEmdzXA5-NNWCNxn2o9aRlTl-CBHFTGgqnM8J1zJenD0eDv_xF9-Rq4V-NUZ8Y3o8PJMM9gn-BE13omrqYceL5nmRM4ZDRYH2POiDtDqebCfO4o3QmZjkDt6rBG1N8BLCPOyglTTybDG-K6hYrM0O53ENj0f9I5dw9IeY2BNCtcnxM8N5PPiOhsuF_kKlMwqsH-XCHO2CZjLe4R3xS8d9XMqHXIfuos8iw9yhH1UiBWeaoLSghTtyPsEfbF3xolYZNAcZyviOUgofpB90HdvzoKeVIl-G_niOO8edHU7CE21-_EPy8ER-PCOeoxeedIHTY3qWKciuQy-iH_Vy4cU1WLOEH30vVNJamMrxiEdv5JBLD7lQGZuTqMP7gPpGVLuJPhGaJNhloGdOVFfmIlR2NGOOPJHk4Cr6fGieIyeDa4emMEekHHcYXGTQH75fXKAWXSJiOhTIE4WaDT-0FD_So1YYg0m0LGiPo1kXdFeDPFfwLBC5TETGsMZH9Ie_FLm2J2i4LBVU7cjRhIuCugGL13CmGI-On2j2HLV6PDoq-iBJRsqQMJKCSMyOE08aolaOKQ6eI--DhM_xPDj47_Ca41NFhcHuOHiGa5ox6kZoQUqaRMdzRG4UozlchUfV41nwHj0VNPky4rzw5ehRKzq-yMWV6EieB-FuOA5v1H7wB39x5giZQYxz_E9ROcsWKOaD6zjCXMcffDP6hcJRrgPVKfkQ_oNyIySzwPxxRhWibzF8Ifly-FIOpsvw4Tn272j-o5qTELmhfvBj5EoR5hLRN8gvhKmI7hk0WXJgRhCdnPiIJpKYIs8VNIqMPkqH_0GTXSSOZymcF2lU7tDO4x8e5M2DnKh-iOFYtMJ5_AJ07YgkLcyNpsZx8DxO5caZBhWVK6BO-Ec-MizEzRvqh2h-EtWf4Il6TEejXtAeTOmU4wd_6I2OhrcQeYlCCf3wG4_RDGEVXkgeJQ784wwackS5CXt0NKVsZCFTyBqRi7mGdnQSRIpdQSM1pGqU4xvRHP8SBr-EPcuDJudxEdlVaEx25Flz1EcYeYj448yLyWIVhNkE6WoQHo2TGeMpnIRP_PiSI08OLU_0IHxwoakedFeKR5ou3OiR5px0_MG3aYL2D-HwBKlzuD_0xUifHeWPb0ezWVtQLRsuXEejjR-ehEVsCVrGI8ePZ_iDJjreIT905dgNK0yG8HlA8w3OI-QODvqDvDu-4wFDPLnxhWiOUsfV5Ihk0YJeoj1KonmQy4sUtImeoBnOoT-a9fiR-6icQ1SPnDoeHNexH2TxYqSPPsgJHfFxCo0uo5QY4DzyKg2aMYqhjcN3PEWZZcdvnG_wcfAPvxK8pLlQLiryHD1v2GGyYJt4sNnwHxPyC_qDXFKMRrPxD807C19T4eETpLmg_wimqDomasL7YEffI_0hHvQRNeyR53ihD7nQo27QzCSuD7_wC2Eq5kj2SPiK0kezPE1wD33Q5HtxPDlyHseN8C6-HU8QSSM09oYnh0EWR6HQkj_CfJmh2Dryl3hOPLmOiiJ8PA-HZD_yHUef4-bRpceXs_iFJ5GGxpFwXjE80uiDHu8TvD52BybRJ8JprgikpB8ARiwQhgDhgBECAySgAAwAoAohgBmACBOMESKZAUxwZYAQSClgjEHCEEOBEA4Qo4Qg1AghjDACIUCYMkIIAoQxhAIBACMEIMKEcNIo6igijAgigQQCABCkJAgAJ5AAEDCElEEEKCEAMAgQYQAQwhgABDPIMKMIEAIAo4xSACJqjBMAEUIIIAAhJaAgRhBEDCNKACYIAQAIgITBQhGqAAFAAKIAA8BAggw0gAhDmUGAIEKcMAwRBZwyxCwDGALACGcIcIgBoQQSBAhIlGMEIGEEEZJoApAQASmgBBGEGQYIIgwCCAAQABiChAEAGCYQEFgwoqxBQBICAEIASGIJI2AgiQAwQAjDJCEMUKKIcMIIQQDyQAmGjDJIGYGMElggAIAAQClDGGQGWCEINEIASgyhACCgjBGACCIYAsIApgDSmAACBBGKCAEMAIQoAIgwACoHBFFEOMYEUIARQAQRCiFABKIAIAABQAIYwQBiBiGAgCKEGUIBA0ECIwBljBATgBXKCKaVYEoAZYAQ0AoJlKACIAQRJAgIAohSVGgjiCJCCCMEEN4xYSBwiAlBqCTGKQAIIwwAA4BgQgBigUJMEAeYQUIQAhQiBAgnlCJACiKIgQwYSSgBwQgPABBIEGAEQkYIoIAEyADADBFkCQWAAVYQI4RCBhhFAAPIAQUcJAgYQSAABgCBADNEKKEcMkAIIQg1CihmhCGOIACIMgAYhAUQQAFikEAQCFCQUAAohwABRAFAICAERAAQAEQIg4EQCBEiEGLASAaIQAAghxESSAkjAbjKAMaQIE5IAgkhChgmFpLIMACMoAYQQJyghhCBEEFAKCKARMYg5IgBABBiHAFIGAICEkZB5QFTTghIoGCEMAGEAkIRKSRJACEAAABCEEAQEdQQogRDggJDAIFCGqEEEYoISwg",
        .duration = 641,
        .fingerprint = "AQABz0qUkZK4oOfhL-CPc4e5C_wW2H2QH9uDL4cvoT8UNQ-eHtsE8cceeFJx-LiiHT-aPzhxoc-Opj_eI5d2hOFyMJRzfDk-QSsu7fBxqZDMHcfxPfDIoPWxv9C1o3yg44d_3Df2GJaUQeeR-cb2HfaPNsdxHj2PJnpwPMN3aPcEMzd-_MeB_Ej4D_CLP8ghHjkJv_jh_UDuQ8xnILwunPg6hF2R8HgzvLhxHVYP_ziJX0eKPnIE1UePMByDJyg7wz_6yELsB8n4oDmDa0Gv40hf6D3CE3_wH6HFaxCPUD9-hNeF5MfWEP3SCGym4-SxnXiGs0mRjEXD6fgl4LmKWrSChzzC33ge9PB3otyJMk-IVC6R8MTNwD9qKQ_CC8kPv4THzEGZS8GPI3x0iGVUxC1hRSizC5VzoamYDi-uR7iKPhGSI82PkiWeB_eHijvsaIWfBCWH5AjjCfVxZ1TQ3CvCTclGnEMfHbnZFA8pjD6KXwd__Cn-Y8e_I9cq6CR-4S9KLXqQcsxxoWh3eMxiHI6TIzyPv0M43YHz4yte-Cv-4D16Hv9F9C9SPUdyGtZRHV-OHEeeGD--BKcjVLOK_NCDXMfx44dzHEiOZ0Z44Rf6DH5R3uiPj4d_PKolJNyRJzyu4_CTD2WOvzjKH9GPb4cUP1Av9EuQd8fGCFee4JlRHi18xQh96NLxkCgfWFKOH6WGeoe4I3za4c5hTscTPEZTES1x8kE-9MQPjT8a8gh5fPgQZtqCFj9MDvp6fDx6NCd07bjx7MLR9AhtnFnQ70GjOcV0opmm4zpY3SOa7HiwdTtyHa6NC4e-HN-OfC5-OP_gLe2QDxfUCz_0w9l65HiPAz9-IaGOUA7-4MZ5CWFOlIfe4yUa6AiZGxf6w0fFxsjTOdC6Itbh4mGD63iPH9-RFy909XAMj7mC5_BvlDyO6kGTZKJxHUd4NDwuZUffw_5RMsde5CWkJAgXnDReNEaP6DTOQ65yaD88HoeX8fge-DSeHo9Qa8cTHc80I-_RoHxx_UHeBxrJw62Q34Kd7MEfpCcu6BLeB1ePw6OO4sOF_sHhmB504WWDZiEu8sKPpkcfCT9xfej0o0lr4T5yNJeOvjmu40w-TDmqHXmYgfFhFy_M7tD1o0cO_B2ms2j-ACEEQgQgAIwzTgAGmBIKIImNQAABwgQATAlhDGCCEIGIIM4BaBgwQBogEBIOESEIA8ARI5xAhxEFmAGAMCKAURKQQpQzRAAkCCBQEAKkQYIYIQQxCixCDADCABMAE0gpJIgyxhEDiCKCCIGAEIgJIQByAhFgGACCACMRQEyBAoxQiHiCBCFOECQFAIgAABR2QAgFjCDMA0AUMIoAIMChQghChASGEGeYEAIAIhgBSErnJPPEGWYAMgw05AhiiGHiBBBGGSCQcQgwRYJwhDDhgCSCSSEIQYwILoyAjAIigBFEUQK8gAYAQ5BCAAjkjCCAEEMZAUQAZQCjCCkpCgFMCCiIcVIAZZgilAQAiSHQECOcQAQIc4QClAHAjDDGkAGAMUoBgyhihgEChFCAAWEIEYwIJYwViAAlHCBIGEIEAEIQAoBwwgwiEBAEEEOoEwBY4wRwxAhBgAcKAESIQAwwIowRFhoBhAE",
        .meta = &.{
            .recordings, 
            .recordingids,
            .releases,
            .releaseids,
            .releasegroups,
            .releasegroupids,
            .tracks,
            .compress,
            .usermeta,
            .sources,
        },
    });
    defer result.deinit();

    log.debug("returned status: {t}", .{result.value.status});

    if (result.value.@"error") |err| {
        log.debug("error: {s} (code: {d})", .{err.message, err.code});
    } else if (result.value.results) |results| {
        for (results) |res| {
            log.debug("id: {s} (score: {d})", .{res.id, res.score});
            for (res.recordings) |recording| {
                log.debug("\tid: {s} (sources: {d})", .{recording.id, recording.sources});
                for (recording.releasegroups) |group| {
                    log.debug("\t\tid: {s}", .{group.id});
                    for (group.releases) |release| {
                        log.debug("\t\t\tid: {s}", .{release.id});
                        for (release.mediums) |medium| {
                            log.debug("\t\t\t\tformat: {t} (position: {d}, track_count: {d})", .{medium.format, medium.position, medium.track_count});
                            for (medium.tracks) |track| {
                                log.debug("\t\t\t\t\tid: {s} (position: {d})", .{track.id, track.position});
                                log.debug("\t\t\t\t\ttitle: {s}", .{track.title});
                                for (track.artists) |artist| {
                                    log.debug("\t\t\t\t\t\tid: {s}", .{artist.id});
                                    log.debug("\t\t\t\t\t\tname: {s}", .{artist.name});
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // var connection = try client.connect(.{ .bytes = "localhost" }, 8080, .plain);
    // defer client.connection_pool.release(connection, client.io);
    //
    // var writer = connection.writer();
    //
    //
    // const headers = &[_]http.Header{
    //     .{ .name = "", .value = "" },
    // };
    //
    // const fetch_result = try client.fetch(.{
    //     .
    // });
    // try writer.writeAll("holla");
    // try writer.flush();
    //
    // try connection.end();



































    // var client: http.Client = .{ .allocator = gpa, .io = io };
    // defer client.deinit();
    //
    // var body: Io.Writer.Allocating = .init(gpa);
    // defer body.deinit();
    //
    // const url = "https://www.google.com?q=zig";
    //
    // const fetch_res = try client.fetch(.{ 
    //     .location = .{ .url = url },
    //     .method = .GET,
    //     .response_writer = &body.writer,
    // });
    //
    // if (fetch_res.status != .ok) {
    //     log.err("Error fetching {s}", .{url});
    // }
    //
    // var res_body = body.toArrayList();
    // defer res_body.deinit(gpa);
    // log.info("response: {s}", .{res_body.items});
    //
    // // var stderr_buf: [1024]u8 = undefined;
    // // const stderr_writer = Io.File.stderr().writer(io, &stderr_buf);
    // // var stderr = stderr_writer.interface;
    // // _ = &stderr;
    //
    // {
    //     const start = Io.Clock.awake.now(io);
    //     const result = try lib.chromaprint.calcFingerprint("assets/Jane!.opus", &.{});
    //     defer lib.chromaprint.chromaprintDealloc(@constCast(result.fingerprint.?.ptr));
    //     const took = start.durationTo(Io.Clock.awake.now(io));
    //     std.debug.print("fp: {?s}\nduration: {f}\ntook: {f}\n", .{result.fingerprint, result.duration, took});
    // }
    // // https://api.acoustid.org/v2/lookup?client=z78sOoLDik&meta=recordingids&duration=187&fingerprint=AQADtIlkJVIYJQmeo3mEZFbyYA_2LMctGY0aVTGqGyeSJzmJXCsDx_Hw4-fRo5mWB_1hRosOPwiVq4KOUMuO78Jk58bzgvE4oXF6XLzwfHDwZEN-KOZQ5AzRRcdz9CG2KjzC00pwIr-BMvFRafpx-ehzMJmUJ_iOHD0DLbGUg5R4onLyIB2ZBjdOUUafKAeZCz8eZEkzaEfOovmM6UcTrkadKMfj480RhmOg8dSQC-fR_EQfpfgOL5py5CSPN4fqGn4e5OtxHWHHwhHDQuP6I5yyuPB-XEqJWvGxb8clEi-PMB-0TYmO6MGPTjtKbUZuHOJxG9-FnLrw49YRvkSzB8p55Lh2sD2qzKBIRmiKzxKuOkfzRJKG6sQx5UXJ4Y5MbDmSHykZpThYacdE5kTjPMGXmbhjJPWDMA_6E4-a5BH6HU2PiykajulRWs6x50h6JUgrHuyaDx9N_IcVMtPxnciTmEh6_HgyB8cULhGJ6jweTkf4vFAdUpiuI_zRjKGE7wGX9DhK5si06IHOHemPPlyMWsWU49mPMzquo46iFOEP9ejzDeGVhvimwD9OEl9YPA_sIIceBfVbaOGSpTgplCPCfJlwSrOB7okkCT48Fn6OPsuRXB_y4-HxcMHR9EKf7MF55FkPTdKO96iFPUHz7EG4UHiOLzzy0Si0XMjjFZcogyl1eD8ePMfTHCHVvNBzIcyPiS1qEU1q5LKToOEuTMSlQNGDZtqhTsd56EN3HWmFE08d7AX1YKXx48-McwizBUIu6fjyBJUeNJoSBT9-5FEkB2WV1NDSIZeCNzOaJTq85-h7hNtGTTjOQ1zCBHVyPD90xugp4gl2gj9-KFeGK3xwSSg7HDsujU0CLdSFUkPO4BQP_3ii6Bm-44liFOlbSM-RH_OR_4FfJD16oS58SSjxfThPfBfCXAqSnRnuxEQTnUQZhWmEZ0dz9Frw6MiDo99x5DlRb8d4HE3GpWC-E7mS4xu2WMqPI6-kBi-u40rxIcwPzS_yDueJJjHxS2ieC88TPGlxSrB1nMczHc2kE9WifPgVNFuyFLUk9D_uJ6j-4KixbdmIsE-DkhlE56gcxcPbFH3RpPuQHwxJmMvx40lYxOpyiHJohIkuPMMzRcQs6UMfeM9wZRrCFyd0hi56xgfyXeiy5HhEEmdzXA5-NNWCNxn2o9aRlTl-CBHFTGgqnM8J1zJenD0eDv_xF9-Rq4V-NUZ8Y3o8PJMM9gn-BE13omrqYceL5nmRM4ZDRYH2POiDtDqebCfO4o3QmZjkDt6rBG1N8BLCPOyglTTybDG-K6hYrM0O53ENj0f9I5dw9IeY2BNCtcnxM8N5PPiOhsuF_kKlMwqsH-XCHO2CZjLe4R3xS8d9XMqHXIfuos8iw9yhH1UiBWeaoLSghTtyPsEfbF3xolYZNAcZyviOUgofpB90HdvzoKeVIl-G_niOO8edHU7CE21-_EPy8ER-PCOeoxeedIHTY3qWKciuQy-iH_Vy4cU1WLOEH30vVNJamMrxiEdv5JBLD7lQGZuTqMP7gPpGVLuJPhGaJNhloGdOVFfmIlR2NGOOPJHk4Cr6fGieIyeDa4emMEekHHcYXGTQH75fXKAWXSJiOhTIE4WaDT-0FD_So1YYg0m0LGiPo1kXdFeDPFfwLBC5TETGsMZH9Ie_FLm2J2i4LBVU7cjRhIuCugGL13CmGI-On2j2HLV6PDoq-iBJRsqQMJKCSMyOE08aolaOKQ6eI--DhM_xPDj47_Ca41NFhcHuOHiGa5ox6kZoQUqaRMdzRG4UozlchUfV41nwHj0VNPky4rzw5ehRKzq-yMWV6EieB-FuOA5v1H7wB39x5giZQYxz_E9ROcsWKOaD6zjCXMcffDP6hcJRrgPVKfkQ_oNyIySzwPxxRhWibzF8Ifly-FIOpsvw4Tn272j-o5qTELmhfvBj5EoR5hLRN8gvhKmI7hk0WXJgRhCdnPiIJpKYIs8VNIqMPkqH_0GTXSSOZymcF2lU7tDO4x8e5M2DnKh-iOFYtMJ5_AJ07YgkLcyNpsZx8DxO5caZBhWVK6BO-Ec-MizEzRvqh2h-EtWf4Il6TEejXtAeTOmU4wd_6I2OhrcQeYlCCf3wG4_RDGEVXkgeJQ784wwackS5CXt0NKVsZCFTyBqRi7mGdnQSRIpdQSM1pGqU4xvRHP8SBr-EPcuDJudxEdlVaEx25Flz1EcYeYj448yLyWIVhNkE6WoQHo2TGeMpnIRP_PiSI08OLU_0IHxwoakedFeKR5ou3OiR5px0_MG3aYL2D-HwBKlzuD_0xUifHeWPb0ezWVtQLRsuXEejjR-ehEVsCVrGI8ePZ_iDJjreIT905dgNK0yG8HlA8w3OI-QODvqDvDu-4wFDPLnxhWiOUsfV5Ihk0YJeoj1KonmQy4sUtImeoBnOoT-a9fiR-6icQ1SPnDoeHNexH2TxYqSPPsgJHfFxCo0uo5QY4DzyKg2aMYqhjcN3PEWZZcdvnG_wcfAPvxK8pLlQLiryHD1v2GGyYJt4sNnwHxPyC_qDXFKMRrPxD807C19T4eETpLmg_wimqDomasL7YEffI_0hHvQRNeyR53ihD7nQo27QzCSuD7_wC2Eq5kj2SPiK0kezPE1wD33Q5HtxPDlyHseN8C6-HU8QSSM09oYnh0EWR6HQkj_CfJmh2Dryl3hOPLmOiiJ8PA-HZD_yHUef4-bRpceXs_iFJ5GGxpFwXjE80uiDHu8TvD52BybRJ8JprgikpB8ARiwQhgDhgBECAySgAAwAoAohgBmACBOMESKZAUxwZYAQSClgjEHCEEOBEA4Qo4Qg1AghjDACIUCYMkIIAoQxhAIBACMEIMKEcNIo6igijAgigQQCABCkJAgAJ5AAEDCElEEEKCEAMAgQYQAQwhgABDPIMKMIEAIAo4xSACJqjBMAEUIIIAAhJaAgRhBEDCNKACYIAQAIgITBQhGqAAFAAKIAA8BAggw0gAhDmUGAIEKcMAwRBZwyxCwDGALACGcIcIgBoQQSBAhIlGMEIGEEEZJoApAQASmgBBGEGQYIIgwCCAAQABiChAEAGCYQEFgwoqxBQBICAEIASGIJI2AgiQAwQAjDJCEMUKKIcMIIQQDyQAmGjDJIGYGMElggAIAAQClDGGQGWCEINEIASgyhACCgjBGACCIYAsIApgDSmAACBBGKCAEMAIQoAIgwACoHBFFEOMYEUIARQAQRCiFABKIAIAABQAIYwQBiBiGAgCKEGUIBA0ECIwBljBATgBXKCKaVYEoAZYAQ0AoJlKACIAQRJAgIAohSVGgjiCJCCCMEEN4xYSBwiAlBqCTGKQAIIwwAA4BgQgBigUJMEAeYQUIQAhQiBAgnlCJACiKIgQwYSSgBwQgPABBIEGAEQkYIoIAEyADADBFkCQWAAVYQI4RCBhhFAAPIAQUcJAgYQSAABgCBADNEKKEcMkAIIQg1CihmhCGOIACIMgAYhAUQQAFikEAQCFCQUAAohwABRAFAICAERAAQAEQIg4EQCBEiEGLASAaIQAAghxESSAkjAbjKAMaQIE5IAgkhChgmFpLIMACMoAYQQJyghhCBEEFAKCKARMYg5IgBABBiHAFIGAICEkZB5QFTTghIoGCEMAGEAkIRKSRJACEAAABCEEAQEdQQogRDggJDAIFCGqEEEYoISwg
}

test {
    std.testing.refAllDecls(@This());
}

