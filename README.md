Dynamic loading in Links

This repo is forked from links-lang/links. All work is based on Links developed by the programming language group in University of Edinburgh and is done by with the help of the group.
In this repo, dynamically load plugins is implemented. Mainly, it supports Links interpreter to load SQL database and library by using flags. Postgresql, mysql and sqlite3 are currently supported, but it's rather easy for users to extend to other SQL database with the API implemented in database.ml. Library provided wraps Ocaml standard library and 

Usage


Links: Linking Theory to Practice for the Web
---------------------------------------------

[![Build Status](https://travis-ci.org/links-lang/links.svg?branch=sessions)](https://travis-ci.org/links-lang/links)

Links helps to build modern Ajax-style applications: those with
significant client- and server-side components.

A typical, modern web program involves many "tiers": part of the
program runs in the web browser, part runs on a web server, and part
runs in specialized systems such as a relational database. To create
such a program, the programmer must master a myriad of languages: the
logic is written in a mixture of Java, Python, and Perl; the
presentation in HTML; the GUI behavior in Javascript; and the queries
are written in SQL or XQuery. There is no easy way to link these: to
be sure, for example, that an HTML form or an SQL query produces the
type of data that the Java code expects. This is called the impedance
mismatch problem.

Links eases the impedance mismatch problem by providing a single
language for all three tiers. The system is responsible for
translating the code into suitable languages for each tier: for
instance, translating some code into Javascript for the browser, some
into Java for the server, and some into SQL to use the database.

Links incorporates ideas proven in other programming languages:
database-query support from Kleisli, web-interaction proposals from
PLT Scheme, and distributed-computing support from Erlang. On top of
this, it adds some new web-centric features of its own.

FEATURES

 * Allows web programs to be written in a single programming language
 * Call-by-value functional language
 * Server / Client annotations
 * AJAX
 * Scalability through defunctionalised server continuations.
 * Statically typed database access a la Kleisli
 * Concurrent processes on the client and the server
 * Statically typed Erlang-esque message passing
 * Polymorphic records and variants
 * An effect system for supporting abstraction over database queries
whilst guaranteeing that they can be efficiently compiled to SQL
