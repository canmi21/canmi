# What goes in an address, and where

Every request says four things, and each has one place. A page and an API divide them the same way:
the rule is about what a part of the request means, not about whether a person or a program reads
the answer.

| Part   | Holds                                           | Removing it                         |
| ------ | ----------------------------------------------- | ----------------------------------- |
| path   | which thing                                     | asks for a different thing, or none |
| query  | which part of it, or in what form               | asks for the same thing, by default |
| body   | what is to change                               | there is nothing to write           |
| header | how the request is made -- credentials, formats | the same thing, asked another way   |

## The path names the thing

**A part that says which thing is asked for is in the path.** An article's slug, a task's id, a
service's name, an object's content id: take one away and the request is about something else, or
about nothing. A thing in a collection is the collection's plural noun, then its id --
`/tasks/{id}`, `/articles/{slug}/likes` -- and a path holds no verb: what is done to the thing is
the method.

**What a page looks like is not the test.** Every article is laid out the same and differs only in
what it says, and its slug is still in its path, because each article is a thing of its own. A
layout changing usually means a different thing is asked for, which is why the two are easy to
confuse; the thing is what decides.

## The query adjusts it

**A part that is optional, has a default and could come in any order is in the query.** A filter,
a range of time, a page of results, an order, a grain, a language, a search's terms: each asks for
the same thing, narrowed or shown another way. `/search?q=` is one thing, the search, asked about
different words; searching photos rather than articles is a different thing, `/search/photos?q=`.

**A lookup takes its inputs in the query.** Where the thing is a computation -- an address from a
latitude and a longitude -- the inputs name nothing that exists before they are asked about, so they
adjust the one thing, the lookup, rather than naming a thing of their own.

**A required parameter in the query is a thing in the wrong place**, unless the route is a lookup.

## The body changes it, and a GET never does

**What is written is in the body, sent by the method that says what the write is** -- `POST` to add
to a collection, `PUT` to set, `DELETE` to remove. **A `GET` changes nothing**: a crawler, a
prefetch and every cache on the way may send one at any time, and a request that wrote would be
made by somebody who never asked it to be.

## A header says how the request is made

Credentials, the formats a client accepts, what a cache may do: these are about the exchange, not
the thing, and two requests that differ only in them ask for the same thing. A version is the
exception: it is in the path, where every layer -- a cache's key, a firewall, a log, a reader --
sees it without parsing anything.
