/*
 * Copyright (C) 2020 Alexander Mikhaylenko <exalm7659@gmail.com>
 * Copyright (C) 2020 James Westman <james@flyingpimonster.net>
 *
 * SPDX-License-Identifier: LGPL-2.1+
 */

#include "config.h"
#include <glib/gi18n-lib.h>
#include <gtk/gtk.h>


#define COMPONENTS_TYPE_REFLOW_BOX (components_reflow_box_get_type())

G_DECLARE_FINAL_TYPE (ComponentsReflowBox, components_reflow_box, COMPONENTS, REFLOW_BOX, GtkContainer)


ComponentsReflowBox *components_reflow_box_new (void);

guint components_reflow_box_get_spacing (ComponentsReflowBox *self);
void  components_reflow_box_set_spacing (ComponentsReflowBox *self,
                                         guint                spacing);

guint components_reflow_box_get_row_spacing (ComponentsReflowBox *self);
void  components_reflow_box_set_row_spacing (ComponentsReflowBox *self,
                                             guint                row_spacing);


struct _ComponentsReflowBox
{
  GtkContainer parent_instance;

  GList *children;

  guint spacing;
  guint row_spacing;
};

G_DEFINE_TYPE (ComponentsReflowBox, components_reflow_box, GTK_TYPE_CONTAINER)

enum {
  PROP_0,
  PROP_SPACING,
  PROP_ROW_SPACING,
  LAST_PROP,
};

static GParamSpec *props[LAST_PROP];


static void
components_reflow_box_init (ComponentsReflowBox *self)
{
  gtk_widget_set_has_window (GTK_WIDGET (self), FALSE);
}

static void
components_reflow_box_get_property (GObject    *object,
                             guint       prop_id,
                             GValue     *value,
                             GParamSpec *pspec)
{
  ComponentsReflowBox *self = COMPONENTS_REFLOW_BOX (object);

  switch (prop_id) {
  case PROP_SPACING:
    g_value_set_uint (value, components_reflow_box_get_spacing (self));
    break;

  case PROP_ROW_SPACING:
    g_value_set_uint (value, components_reflow_box_get_row_spacing (self));
    break;

  default:
    G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
  }
}

static void
components_reflow_box_set_property (GObject      *object,
                             guint         prop_id,
                             const GValue *value,
                             GParamSpec   *pspec)
{
  ComponentsReflowBox *self = COMPONENTS_REFLOW_BOX (object);

  switch (prop_id) {
  case PROP_SPACING:
    components_reflow_box_set_spacing (self, g_value_get_uint (value));
    break;

  case PROP_ROW_SPACING:
    components_reflow_box_set_row_spacing (self, g_value_get_uint (value));
    break;

  default:
    G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
  }
}

/**
 * components_reflow_box_set_spacing:
 * @self: a #ComponentsReflowBox
 * @spacing: the spacing
 *
 * Sets the spacing for @self.
 *
 * Since: 0.0.14
 */
void
components_reflow_box_set_spacing (ComponentsReflowBox *self,
                            guint         spacing)
{
  if (self->spacing == spacing)
    return;

  self->spacing = spacing;
  gtk_widget_queue_resize (GTK_WIDGET (self));

  g_object_notify_by_pspec (G_OBJECT (self), props[PROP_SPACING]);
}

/**
 * components_reflow_box_get_spacing:
 * @self: a #ComponentsReflowBox
 *
 * Gets the spacing for @self.
 *
 * Returns: the spacing for @self.
 *
 * Since: 0.0.14
 */
guint
components_reflow_box_get_spacing (ComponentsReflowBox *self)
{
  return self->spacing;
}

/**
 * components_reflow_box_set_row_spacing:
 * @self: a #ComponentsReflowBox
 * @row_spacing: the row spacing
 *
 * Sets the row spacing for @self.
 *
 * Since: 0.0.14
 */
void
components_reflow_box_set_row_spacing (ComponentsReflowBox *self,
                                guint          row_spacing)
{
  if (self->row_spacing == row_spacing)
    return;

  self->row_spacing = row_spacing;
  gtk_widget_queue_resize (GTK_WIDGET (self));

  g_object_notify_by_pspec (G_OBJECT (self), props[PROP_ROW_SPACING]);
}

/**
 * components_reflow_box_get_row_spacing:
 * @self: a #ComponentsReflowBox
 *
 * Gets the row spacing for @self.
 *
 * Returns: the row spacing for @self.
 *
 * Since: 0.0.14
 */
guint
components_reflow_box_get_row_spacing (ComponentsReflowBox *self)
{
  return self->row_spacing;
}


static void
allocate_row (ComponentsReflowBox  *self,
              GtkAllocation *allocation,
              gint           y,
              GList         *row_start,
              GList         *next_row,
              gint           row_height,
              gint           extra_space,
              gint           n_expand_children)
{
  gboolean rtl;
  gint x = 0;
  gint expand_per_child = 0;

  if (row_start == NULL)
    return;

  rtl = gtk_widget_get_direction (GTK_WIDGET (self)) == GTK_TEXT_DIR_RTL;
  if (rtl)
    x = allocation->width;

  if (n_expand_children > 0) {
    expand_per_child = extra_space / n_expand_children;
  } else {
    GtkAlign align;
    align = gtk_widget_get_halign (GTK_WIDGET (self));
    if (align == GTK_ALIGN_CENTER) {
      if (rtl)
        x -= (extra_space / 2);
      else
        x += (extra_space / 2);
    } else if (align == GTK_ALIGN_END) {
      if (rtl)
        x -= extra_space;
      else
        x += extra_space;
    }
  }

  for (GList *l = row_start; l != NULL && l != next_row; l = l->next) {
    GtkWidget *child = GTK_WIDGET (l->data);
    int w, min_w;
    GtkAllocation child_alloc;

    if (!gtk_widget_get_visible (child))
      continue;

    gtk_widget_get_preferred_width (child, &min_w, &w);
    w = CLAMP (w, min_w, allocation->width);

    if (gtk_widget_get_hexpand (child)) {
      w += expand_per_child;
    }

    if (rtl)
      x -= w;

    child_alloc.x = x + allocation->x;

    if (rtl)
      x -= self->spacing;
    else
      x += w + self->spacing;

    child_alloc.y = y + allocation->y;
    child_alloc.width = w;
    child_alloc.height = row_height;

    gtk_widget_size_allocate (child, &child_alloc);
  }
}

static gint
calculate_sizes (ComponentsReflowBox  *self,
                 GtkAllocation *allocation,
                 gboolean       dry_run)
{
  gint x = 0;
  gint y = 0;
  gint row_height = 0;

  GList *row_start = self->children;
  gint n_expand_children = 0;

  for (GList *l = self->children; l != NULL; l = l->next) {
    GtkWidget *child = GTK_WIDGET (l->data);
    int w, h, min_w;

    if (!gtk_widget_get_visible (child))
      continue;

    gtk_widget_get_preferred_width (child, &min_w, &w);
    gtk_widget_get_preferred_height (child, NULL, &h);

    w = CLAMP (w, min_w, allocation->width);

    if (x + w > allocation->width) {
      /* no more space on this row, create a new one */

      /* first, do the allocations for the previous row, if needed */
      if (!dry_run) {
        allocate_row (self, allocation, y, row_start, l, row_height,
                      allocation->width + self->spacing - x, n_expand_children);
      }

      /* now reset everything for the next row */
      x = 0;
      y += row_height + self->row_spacing;
      row_height = 0;
      n_expand_children = 0;
      row_start = l;
    }

    if (gtk_widget_get_hexpand (child))
      n_expand_children ++;

    row_height = MAX (row_height, h);

    x += w + self->spacing;
  }

  if (!dry_run) {
    /* allocate the last row */
    allocate_row (self, allocation, y, row_start, NULL, row_height,
                  allocation->width + self->spacing - x, n_expand_children);
  }

  return y + row_height;
}

static void
components_reflow_box_size_allocate(GtkWidget      *widget,
                             GtkAllocation  *allocation)
{
  ComponentsReflowBox *self = COMPONENTS_REFLOW_BOX (widget);

  calculate_sizes(self, allocation, FALSE);
  GTK_WIDGET_CLASS (components_reflow_box_parent_class)->size_allocate (widget, allocation);
}

static GtkSizeRequestMode
components_reflow_box_get_request_mode(GtkWidget *widget)
{
  COMPONENTS_REFLOW_BOX (widget);
  return GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH;
}

static void
components_reflow_box_get_preferred_width(GtkWidget *widget,
                                   gint      *minimum_width,
                                   gint      *natural_width)
{
  ComponentsReflowBox *self = COMPONENTS_REFLOW_BOX (widget);

  gint min = 0;
  gint nat = 0;

  for (GList *l = self->children; l != NULL; l = l->next) {
    GtkWidget *child = GTK_WIDGET (l->data);
    int child_min, child_nat;

    if (!gtk_widget_get_visible (child))
      continue;

    gtk_widget_get_preferred_width (child, &child_min, &child_nat);

    min = MAX (min, child_min);
    nat += child_nat + self->spacing;
  }

  /* remove the extra spacing, avoid off-by-one error */
  if (self->children != NULL)
    nat -= self->spacing;

  if (minimum_width)
    *minimum_width = min;
  if (natural_width)
    *natural_width = nat;
}

static void
components_reflow_box_get_preferred_width_for_height (GtkWidget *widget,
                                               G_GNUC_UNUSED gint height,
                                               gint      *minimum_width,
                                               gint      *natural_width)
{
  components_reflow_box_get_preferred_width (widget, minimum_width, natural_width);
}

static void
components_reflow_box_get_preferred_height_for_width (GtkWidget *widget,
                                               gint       width,
                                               gint      *minimum_height,
                                               gint      *natural_height)
{
  ComponentsReflowBox *self = COMPONENTS_REFLOW_BOX (widget);

  GtkAllocation allocation;
  gint h;

  allocation.width = width;
  h = calculate_sizes (self, &allocation, TRUE);

  if (minimum_height)
    *minimum_height = h;
  if (natural_height)
    *natural_height = h;
}


static void
components_reflow_box_add (GtkContainer *container,
                    GtkWidget    *widget)
{
  ComponentsReflowBox *self = COMPONENTS_REFLOW_BOX (container);

  self->children = g_list_append (self->children, widget);
  gtk_widget_set_parent (widget, GTK_WIDGET (self));
}

static void
components_reflow_box_remove (GtkContainer *container,
                       GtkWidget    *widget)
{
  ComponentsReflowBox *self = COMPONENTS_REFLOW_BOX (container);

  gtk_widget_unparent (widget);
  self->children = g_list_remove (self->children, widget);
}

static void
components_reflow_box_forall (GtkContainer *container,
                       G_GNUC_UNUSED gboolean include_internals,
                       GtkCallback   callback,
                       gpointer      callback_data)
{
  ComponentsReflowBox *self = COMPONENTS_REFLOW_BOX (container);

  // while loop instead of for loop in case the callback removes children
  GList *l = self->children;
  while (l != NULL) {
    GtkWidget *child = GTK_WIDGET (l->data);
    l = l->next;
    callback (child, callback_data);
  }
}

static void
components_reflow_box_class_init (ComponentsReflowBoxClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS (klass);
  GtkWidgetClass *widget_class = GTK_WIDGET_CLASS (klass);
  GtkContainerClass *container_class = GTK_CONTAINER_CLASS (klass);

  object_class->set_property = components_reflow_box_set_property;
  object_class->get_property = components_reflow_box_get_property;

  widget_class->size_allocate = components_reflow_box_size_allocate;
  widget_class->get_request_mode = components_reflow_box_get_request_mode;
  widget_class->get_preferred_width = components_reflow_box_get_preferred_width;
  widget_class->get_preferred_width_for_height = components_reflow_box_get_preferred_width_for_height;
  widget_class->get_preferred_height_for_width = components_reflow_box_get_preferred_height_for_width;

  container_class->add = components_reflow_box_add;
  container_class->remove = components_reflow_box_remove;
  container_class->forall = components_reflow_box_forall;

  /**
   * ComponentsReflowBox:spacing:
   *
   * The spacing between children
   *
   * Since: 0.0.14
   */
  props[PROP_SPACING] =
    g_param_spec_uint ("spacing",
                       "Spacing",
                       "Spacing between children",
                       0,
                       G_MAXUINT,
                       0,
                       G_PARAM_READWRITE | G_PARAM_EXPLICIT_NOTIFY);

  /**
   * ComponentsReflowBox:row-spacing:
   *
   * The spacing between rows of children
   *
   * Since: 0.0.14
   */
  props[PROP_ROW_SPACING] =
    g_param_spec_uint ("row-spacing",
                       "Row spacing",
                       "Spacing between rows of children",
                       0,
                       G_MAXUINT,
                       0,
                       G_PARAM_READWRITE | G_PARAM_EXPLICIT_NOTIFY);

  g_object_class_install_properties (object_class, LAST_PROP, props);
}

/**
 * components_reflow_box_new:
 *
 * Create a new #ComponentsReflowBox widget.
 *
 * Returns: The newly created #ComponentsReflowBox widget
 *
 * Since: 0.0.14
 */
ComponentsReflowBox *
components_reflow_box_new (void)
{
  return g_object_new (COMPONENTS_TYPE_REFLOW_BOX, NULL);
}



