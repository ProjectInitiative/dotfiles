// SPDX-License-Identifier: GPL-2.0
/*
 * Media graph of each camera, so that libcamera's simple pipeline handler can
 * drive it (the front one through its software ISP):
 *
 *   "ov02c10 14-0036" (sensor) -> "surface-ultra-seninf" -> video node
 *   "vd55g1 18-0010"  (sensor) -> "surface-ultra-seninf" -> video node
 *
 * The sensors and seninf are programmed by this driver (sucam_hw.c), so the
 * subdevs only describe the one fixed mode of each camera and carry the
 * sensor controls; the stream itself starts at the video node's STREAMON.
 */
#include <linux/i2c.h>
#include <media/v4l2-subdev.h>
#include "sucam.h"

static const struct sucam_cfg *sd_cfg(struct v4l2_subdev *sd)
{
	return ((struct sucam *)v4l2_get_subdevdata(sd))->cfg;
}

static void sucam_mbus_fmt(const struct sucam_cfg *cfg, struct v4l2_mbus_framefmt *f)
{
	f->width = cfg->width;
	f->height = cfg->height;
	f->code = cfg->mbus;
	f->field = V4L2_FIELD_NONE;
	f->colorspace = V4L2_COLORSPACE_RAW;
	f->ycbcr_enc = V4L2_YCBCR_ENC_DEFAULT;
	f->quantization = V4L2_QUANTIZATION_FULL_RANGE;
	f->xfer_func = V4L2_XFER_FUNC_NONE;
}

static int sucam_enum_mbus_code(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
				struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index)
		return -EINVAL;
	code->code = sd_cfg(sd)->mbus;
	return 0;
}

static int sucam_enum_frame_size(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
				 struct v4l2_subdev_frame_size_enum *fse)
{
	const struct sucam_cfg *cfg = sd_cfg(sd);

	if (fse->index || fse->code != cfg->mbus)
		return -EINVAL;
	fse->min_width = fse->max_width = cfg->width;
	fse->min_height = fse->max_height = cfg->height;
	return 0;
}

/* one fixed mode: set_fmt reports it back, whatever was asked */
static int sucam_get_fmt(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
			 struct v4l2_subdev_format *fmt)
{
	sucam_mbus_fmt(sd_cfg(sd), &fmt->format);
	return 0;
}

/* the sensor array and the part of it that reaches memory */
static int sucam_get_selection(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
			       struct v4l2_subdev_selection *sel)
{
	switch (sel->target) {
	case V4L2_SEL_TGT_NATIVE_SIZE:
	case V4L2_SEL_TGT_CROP_BOUNDS:
		sel->r = sd_cfg(sd)->native;
		return 0;
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP:
		sel->r = sd_cfg(sd)->crop;
		return 0;
	}
	return -EINVAL;
}

static const struct v4l2_subdev_pad_ops sucam_sensor_pad_ops = {
	.enum_mbus_code = sucam_enum_mbus_code,
	.enum_frame_size = sucam_enum_frame_size,
	.get_fmt = sucam_get_fmt,
	.set_fmt = sucam_get_fmt,
	.get_selection = sucam_get_selection,
};

static const struct v4l2_subdev_ops sucam_sensor_ops = {
	.pad = &sucam_sensor_pad_ops,
};

static const struct v4l2_subdev_pad_ops sucam_seninf_pad_ops = {
	.enum_mbus_code = sucam_enum_mbus_code,
	.enum_frame_size = sucam_enum_frame_size,
	.get_fmt = sucam_get_fmt,
	.set_fmt = sucam_get_fmt,
};

static const struct v4l2_subdev_ops sucam_seninf_ops = {
	.pad = &sucam_seninf_pad_ops,
};

static const struct media_entity_operations sucam_entity_ops = {
	.link_validate = v4l2_subdev_link_validate,
};

/*
 * The media device's driver name is what libcamera matches its pipeline
 * handlers on (16 bytes in media_device_info). mdev_name=mtk-seninf lets a
 * stock libcamera, whose simple pipeline already lists that name, drive the
 * camera before a "surface-ultra" entry exists there.
 */
static char *mdev_name = "surface-ultra";
module_param(mdev_name, charp, 0444);
MODULE_PARM_DESC(mdev_name, "media device driver name (default surface-ultra)");

/* before v4l2_device_register(): the v4l2_device has to know the media device */
int sucam_mc_init(struct sucam *cam)
{
	struct media_device *mdev = &cam->mdev;

	mdev->dev = cam->dev;
	strscpy(mdev->driver_name, mdev_name, sizeof(mdev->driver_name));
	strscpy(mdev->model, cam->cfg->card, sizeof(mdev->model));
	snprintf(mdev->bus_info, sizeof(mdev->bus_info), "platform:%s", dev_name(cam->dev));
	media_device_init(mdev);
	cam->v4l2_dev.mdev = mdev;
	return 0;
}

static int sucam_add_subdev(struct sucam *cam, struct v4l2_subdev *sd,
			    const struct v4l2_subdev_ops *ops, const char *name, u32 function,
			    struct media_pad *pads, unsigned int npads)
{
	int ret;

	v4l2_subdev_init(sd, ops);
	sd->owner = THIS_MODULE;
	sd->dev = cam->dev;
	sd->flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	strscpy(sd->name, name, sizeof(sd->name));
	sd->entity.function = function;
	sd->entity.ops = &sucam_entity_ops;
	v4l2_set_subdevdata(sd, cam);
	ret = media_entity_pads_init(&sd->entity, npads, pads);
	return ret ?: v4l2_device_register_subdev(&cam->v4l2_dev, sd);
}

/* after video_register_device(): subdevs, links, then the /dev/media node */
int sucam_mc_register(struct sucam *cam)
{
	char name[sizeof(cam->sensor_sd.name)];
	int ret;

	/* the name the in-tree sensor driver would register (libcamera's model) */
	if (cam->sensor)
		snprintf(name, sizeof(name), "%s %d-%04x", cam->cfg->sensor,
			 i2c_adapter_id(cam->sensor->adapter), cam->sensor->addr);
	else
		strscpy(name, cam->cfg->sensor, sizeof(name));
	cam->sensor_pad.flags = MEDIA_PAD_FL_SOURCE;
	ret = sucam_add_subdev(cam, &cam->sensor_sd, &sucam_sensor_ops, name,
			       MEDIA_ENT_F_CAM_SENSOR, &cam->sensor_pad, 1);
	if (ret)
		return ret;
	cam->sensor_sd.ctrl_handler = &cam->ctrls;

	cam->seninf_pads[0].flags = MEDIA_PAD_FL_SINK;
	cam->seninf_pads[1].flags = MEDIA_PAD_FL_SOURCE;
	ret = sucam_add_subdev(cam, &cam->seninf_sd, &sucam_seninf_ops, "surface-ultra-seninf",
			       MEDIA_ENT_F_VID_IF_BRIDGE, cam->seninf_pads, 2);
	if (ret)
		goto err;

	ret = media_create_pad_link(&cam->sensor_sd.entity, 0, &cam->seninf_sd.entity, 0,
				    MEDIA_LNK_FL_ENABLED | MEDIA_LNK_FL_IMMUTABLE);
	ret = ret ?: media_create_pad_link(&cam->seninf_sd.entity, 1, &cam->vdev.entity, 0,
					   MEDIA_LNK_FL_ENABLED | MEDIA_LNK_FL_IMMUTABLE);
	ret = ret ?: v4l2_device_register_subdev_nodes(&cam->v4l2_dev);
	ret = ret ?: media_device_register(&cam->mdev);
	if (ret)
		goto err;
	return 0;

err:
	sucam_mc_unregister(cam);
	return ret;
}

void sucam_mc_unregister(struct sucam *cam)
{
	media_device_unregister(&cam->mdev);
	v4l2_device_unregister_subdev(&cam->seninf_sd);
	v4l2_device_unregister_subdev(&cam->sensor_sd);
	media_entity_cleanup(&cam->seninf_sd.entity);
	media_entity_cleanup(&cam->sensor_sd.entity);
}
