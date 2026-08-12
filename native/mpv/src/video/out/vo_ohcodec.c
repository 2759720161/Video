/*
 * This file is part of mpv.
 *
 * mpv is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * mpv is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with mpv.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_oh.h>
#include <native_window/external_window.h>

#include "common/common.h"
#include "vo.h"
#include "video/mp_image.h"
#include "video/hwdec.h"
#include "ohos_common.h"

struct priv {
    struct mp_image *next_image;
    struct mp_hwdec_ctx hwctx;
};

static int preinit(struct vo *vo)
{
    struct priv *p = vo->priv;

    vo->hwdec_devs = hwdec_devices_create();

    AVBufferRef *device_ref = vo_ohos_create_ohcodec_device_ref(vo);
    if (!device_ref) {
        MP_VERBOSE(vo, "Failed to create ohcodec hwdevice_ctx\n");
        return -1;
    }

    p->hwctx = (struct mp_hwdec_ctx){
        .driver_name = "ohcodec",
        .av_device_ref = device_ref,
        .hw_imgfmt = IMGFMT_OHCODEC,
    };

    hwdec_devices_add(vo->hwdec_devs, &p->hwctx);
    return 0;
}

static void flip_page(struct vo *vo)
{
    struct priv *p = vo->priv;
    if (!p->next_image)
        return;

    vo_ohos_ohcodec_discard(p->next_image);
    mp_image_unrefp(&p->next_image);
}

static bool draw_frame(struct vo *vo, struct vo_frame *frame)
{
    struct priv *p = vo->priv;

    mp_image_t *mpi = NULL;
    if (!frame->redraw && !frame->repeat)
        mpi = mp_image_new_ref(frame->current);

    talloc_free(p->next_image);
    p->next_image = mpi;
    return VO_TRUE;
}

static int query_format(struct vo *vo, int format)
{
    return format == IMGFMT_OHCODEC;
}

static int control(struct vo *vo, uint32_t request, void *data)
{
    return VO_NOTIMPL;
}

static int reconfig(struct vo *vo, struct mp_image_params *params)
{
    return 0;
}

static void uninit(struct vo *vo)
{
    struct priv *p = vo->priv;
    mp_image_unrefp(&p->next_image);

    hwdec_devices_remove(vo->hwdec_devs, &p->hwctx);
    av_buffer_unref(&p->hwctx.av_device_ref);

    vo_ohos_uninit(vo);
}

const struct vo_driver video_out_ohcodec = {
    .description = "HarmonyOS (OHCodec Surface)",
    .name = "ohcodec",
    .caps = VO_CAP_NORETAIN,
    .preinit = preinit,
    .query_format = query_format,
    .control = control,
    .draw_frame = draw_frame,
    .flip_page = flip_page,
    .reconfig = reconfig,
    .uninit = uninit,
    .priv_size = sizeof(struct priv),
};
