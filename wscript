#! /usr/bin/env python
# encoding: utf-8
#
# Copyright 2011 Yorba Foundation

# the following two variables are used by the target "waf dist"
VERSION = '0.0.0+trunk'
APPNAME = 'geary'

# these variables are mandatory ('/' are converted automatically)
top = '.'
out = 'build'

def options(opt):
	opt.load('compiler_c')
	opt.load('vala')

def configure(conf):
	conf.load('compiler_c vala')
	
	conf.check_vala((0, 12, 0))
	
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
		package='gtk+-2.0',
		uselib_store='GTK',
		atleast_version='2.22.0',
		mandatory=1,
		args='--cflags --libs')
	
	conf.check_cfg(
		package='unique-1.0',
		uselib_store='UNIQUE',
		atleast_version='1.0.0',
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

def build(bld):
	bld.env.append_value('CFLAGS', ['-O2', '-g'])
	bld.env.append_value('LINKFLAGS', ['-O2', '-g'])
	bld.env.append_value('VALAFLAGS', ['-g', '--enable-checking', '--fatal-warnings'])
	
	bld.recurse('src')

