#! /usr/bin/env python
# encoding: utf-8
#
# Copyright 2011 Yorba Foundation

import shutil
import os.path
import subprocess

# the following two variables are used by the target "waf dist"
VERSION = '0.0.0+trunk'
APPNAME = 'geary'

# these variables are mandatory ('/' are converted automatically)
top = '.'
out = 'build'

def options(opt):
	opt.load('compiler_c')
	opt.load('vala')
	opt.load('glib2')

def configure(conf):
	conf.load('compiler_c vala glib2')
	
	conf.check_vala((0, 14, 0))
	
	conf.check_cfg(
		package='glib-2.0',
		uselib_store='GLIB',
		atleast_version='2.28.6',
		mandatory=1,
		args='--cflags --libs')
	
	conf.check_cfg(
		package='gio-2.0',
		uselib_store='GIO',
		atleast_version='2.28.0',
		mandatory=1,
		args='--cflags --libs')
	
	conf.check_cfg(
		package='gee-1.0',
		uselib_store='GEE',
		atleast_version='0.6.0',
		mandatory=1,
		args='--cflags --libs')
	
	conf.check_cfg(
		package='gtk+-3.0',
		uselib_store='GTK',
		atleast_version='3.0.',
		mandatory=1,
		args='--cflags --libs')
	
	conf.check_cfg(
		package='unique-3.0',
		uselib_store='UNIQUE',
		atleast_version='3.0.0',
		mandatory=1,
		args='--cflags --libs')
	
	conf.check_cfg(
		package='sqlite3',
		uselib_store='SQLITE',
		atleast_version='3.7.4',
		mandatory=1,
		args='--cflags --libs')
	
	conf.check_cfg(
		package='sqlheavy-0.1',
		uselib_store='SQLHEAVY',
		atleast_version='0.0.1',
		mandatory=1,
		args='--cflags --libs')
	
	conf.check_cfg(
		package='gmime-2.4',
		uselib_store='GMIME',
		atleast_version='2.4.14',
		mandatory=1,
		args='--cflags --libs')
		
	conf.check_cfg(
		package='gnome-keyring-1',
		uselib_store='GNOME-KEYRING',
		atleast_version='2.32.0',
		mandatory=1,
		args='--cflags --libs')

def build(bld):
	bld.add_post_fun(post_build)
	
	bld.env.append_value('CFLAGS', ['-O2', '-g', '-D_PREFIX="' + bld.env.PREFIX + '"'])
	bld.env.append_value('LINKFLAGS', ['-O2', '-g'])
	bld.env.append_value('VALAFLAGS', ['-g', '--enable-checking', '--fatal-warnings'])	
	
	bld.recurse('src')

def post_build(bld):
	# Copy executable to root folder.
	geary_path = 'build/src/client/geary'
	
	if os.path.isfile(geary_path) :
		shutil.copy2(geary_path, 'geary')
	
	# Compile schemas for local (non-intall) build.
	client_build_path = 'build/src/client'
	shutil.copy2('src/client/org.yorba.geary.gschema.xml', client_build_path)
	subprocess.call(['glib-compile-schemas', client_build_path])

