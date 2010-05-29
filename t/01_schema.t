use strict;
use warnings;

use Test::More;
plan tests => 88;
use Test::Exception;
use_ok 'Avro::Schema';

dies_ok { Avro::Schema->new } "Should use parse() or instantiate the subclass";

throws_ok { Avro::Schema->parse(q()) } "Avro::Schema::Error::Parse";
throws_ok { Avro::Schema->parse(q(test)) } "Avro::Schema::Error::Parse";
throws_ok { Avro::Schema->parse(q({"type": t})) }
            "Avro::Schema::Error::Parse";
throws_ok { Avro::Schema->parse(q({"type": t})) }
            "Avro::Schema::Error::Parse";

my $s = Avro::Schema->parse(q("string"));
isa_ok $s, 'Avro::Schema::Base';
isa_ok $s, 'Avro::Schema::Primitive',
is $s->type, "string", "type is string";

my $s2 = Avro::Schema->parse(q({"type": "string"}));
isa_ok $s2, 'Avro::Schema::Primitive';
is $s2->type, "string", "type is string";
is $s, $s2, "string Schematas are singletons";

## Records
{
    my $s3 = Avro::Schema::Record->new(
        struct => {
            name => 'saucisson',
            fields => [
                { name => 'a', type => 'long'   },
                { name => 'b', type => 'string' },
            ],
        },
    );

    isa_ok $s3, 'Avro::Schema::Record';
    is $s3->type, 'record', "this is a record type";
    is $s3->fullname, 'saucisson', "correct name";
    is $s3->fields->[0]{name}, 'a', 'a';
    is $s3->fields->[0]{type}, Avro::Schema::Primitive->new(type => 'long'), 'long';
    is $s3->fields->[1]{name}, 'b', 'b';
    is $s3->fields->[1]{type}, Avro::Schema::Primitive->new(type => 'string'), 'str';

    ## self-reference
    $s3 = Avro::Schema::Record->new(
        struct => {
            name => 'saucisson',
            fields => [
                { name => 'a', type => 'long'      },
                { name => 'b', type => 'saucisson' },
            ],
        },
    );
    isa_ok $s3, 'Avro::Schema::Record';
    is $s3->fullname, 'saucisson', "correct name";
    is $s3->fields->[0]{name}, 'a', 'a';
    is $s3->fields->[0]{type}, Avro::Schema::Primitive->new(type => 'long'), 'long';
    is $s3->fields->[1]{name}, 'b', 'b';
    is $s3->fields->[1]{type}, $s3, 'self!';

    ## serialize
    my $string = $s3->to_string;
    like $string, qr/saucisson/, "generated string has 'saucisson'";
    my $s3bis = Avro::Schema->parse($string);
    is_deeply $s3bis->to_struct, $s3->to_struct,
        'regenerated structure matches original';

    ## record fields can have defaults
    my @good_ints = (2, -1, -(2**31 - 1), 2_147_483_647, "2147483647"  );
    my @bad_ints = ("", "string", 9.22337204, 9.22337204E10, 2**32 - 1,
                    4_294_967_296, 9_223_372_036_854_775_807, \"2");
    my @good_longs = (1, 2, -3, 9_223_372_036_854_775_807, 3e10);
    my @bad_longs = (9.22337204, 9.22337204E10 + 0.1,
                    9_223_372_036_854_775_808, \"2");

    for (@good_ints) {
        my $s4 = Avro::Schema::Record->new(
            struct => { name => 'saucisson',
                fields => [
                    { name => 'a', type => 'int', default => $_ },
                ],
            },
        );
        is $s4->fields->[0]{default}, $_, "default $_";
    }
    for (@good_longs) {
        my $s4 = Avro::Schema::Record->new(
            struct => { name => 'saucisson',
                fields => [
                    { name => 'a', type => 'long', default => $_ },
                ],
            },
        );
        is $s4->fields->[0]{default}, $_, "default $_";
    }
    for (@bad_ints) {
        throws_ok  { Avro::Schema::Record->new(
            struct => { name => 'saucisson',
                fields => [
                    { name => 'a', type => 'int', default => $_ },
                ],
            },
        ) } "Avro::Schema::Error::Parse", "invalid default: $_";
    }
    for (@bad_longs) {
        throws_ok  { Avro::Schema::Record->new(
            struct => { name => 'saucisson',
                fields => [
                    { name => 'a', type => 'long', default => $_ },
                ],
            },
        ) } "Avro::Schema::Error::Parse", "invalid default: $_";
    }

    ## default of more complex types
    throws_ok {
        Avro::Schema::Record->new(
            struct => { name => 'saucisson',
                fields => [
                    { name => 'a', type => 'union', default => 1 },
                ],
            },
        )
    } "Avro::Schema::Error::Parse", "union don't have default: $@";

    my $s4 = Avro::Schema->parse_struct(
        {
            type => 'record',
            name => 'saucisson',
            fields => [
                { name => 'string', type => 'string', default => "something" },
                { name => 'map', type => { type => 'map', values => 'long' }, default => {a => 2} },
                { name => 'array', type => { type => 'array', items => 'long' }, default => [1, 2] },
                { name => 'bytes', type => 'bytes', default => "something" },
                { name => 'null', type => 'null', default => undef },
            ],
        },
    );
    is $s4->fields->[0]{default}, "something", "string default";
    is_deeply $s4->fields->[1]{default}, { a => 2 }, "map default";
    is_deeply $s4->fields->[2]{default}, [1, 2], "array default";
    is $s4->fields->[3]{default}, "something", "bytes default";
    is $s4->fields->[4]{default}, undef, "null default";
    ## TODO: technically we should verify that default map/array match values
    ## and items types defined

    ## ordering
    for (qw(ascending descending ignore)) {
        my $s4 = Avro::Schema::Record->new(
            struct => {
                name => 'saucisson',
                fields => [
                    { name => 'a', type => 'int', order => $_ },
                ],
            },
        );
        is $s4->fields->[0]{order}, $_, "order set to $_";
    }
    for (qw(DESCEND ascend DESCENDING ASCENDING)) {
        throws_ok  { Avro::Schema::Record->new(
            struct => { name => 'saucisson',
                fields => [
                    { name => 'a', type => 'long', order => $_ },
                ],
            },
        ) } "Avro::Schema::Error::Parse", "invalid order: $_";
    }
}

## Unions
{
    my $spec_example = <<EOJ;
{
  "type": "record",
  "name": "LongList",
  "fields" : [
    {"name": "value", "type": "long"},
    {"name": "next", "type": ["LongList", "null"]}
  ]
}
EOJ
    my $schema = Avro::Schema->parse($spec_example);
    is $schema->type, 'record', "type record";
    is $schema->fullname, 'LongList', "name is LongList";

    ## Union checks
    # can only contain one type

    $s = <<EOJ;
["null", "null"]
EOJ
    throws_ok { Avro::Schema->parse($s) }
              'Avro::Schema::Error::Parse';

    $s = <<EOJ;
["long", "string", "float", "string"]
EOJ
    throws_ok { Avro::Schema->parse($s) }
              'Avro::Schema::Error::Parse';

    $s = <<EOJ;
{
  "type": "record",
  "name": "embed",
  "fields": [
    {"name": "value", "type":
        { "type": "record", "name": "rec1",  "fields": [
            { "name": "str1", "type": "string"}
        ] }
    },
    {"name": "next", "type": ["embed", "rec1", "embed"] }
  ]
}
EOJ
    throws_ok { Avro::Schema->parse($s) }
          'Avro::Schema::Error::Parse',
          'two records with same name in the union';

    $s = <<EOJ;
{
  "type": "record",
  "name": "embed",
  "fields": [
    {"name": "value", "type":
        { "type": "record", "name": "rec1",  "fields": [
            { "name": "str1", "type": "string"}
        ] }
    },
    {"name": "next", "type": ["embed", "rec1"] }
  ]
}
EOJ
    lives_ok { Avro::Schema->parse($s) }
             'two records of different names in the union';

    # cannot directly embed another union
    $s = <<EOJ;
["long", ["string", "float"], "string"]
EOJ
    throws_ok { Avro::Schema->parse($s) }
             'Avro::Schema::Error::Parse', "cannot embed union in union";
}

## Enums!
{
    my $s = <<EOJ;
{ "type": "enum", "name": "theenum", "symbols": [ "A", "B" ]}
EOJ
    my $schema = Avro::Schema->parse($s);
    is $schema->type, 'enum', "enum";
    is $schema->fullname, 'theenum', "fullname";
    is $schema->symbols->[0], "A", "symbol A";
    is $schema->symbols->[1], "B", "symbol B";
    my $string = $schema->to_string;
    my $s2 = Avro::Schema->parse($string);
    is_deeply $s2, $schema, "reserialized identically";
}

## Arrays
{
    my $s = <<EOJ;
{ "type": "array", "items": "string" }
EOJ
    my $schema = Avro::Schema->parse($s);
    is $schema->type, 'array', "array";
    is $schema->items, 'string', "type of items is string";
    my $string = $schema->to_string;
    my $s2 = Avro::Schema->parse($string);
    is_deeply $s2, $schema, "reserialized identically";
}

## Maps
{
    my $s = <<EOJ;
{ "type": "map", "values": "string" }
EOJ
    my $schema = Avro::Schema->parse($s);
    is $schema->type, 'map', "map";
    is $schema->values, 'string', "type of values is string";
    my $string = $schema->to_string;
    my $s2 = Avro::Schema->parse($string);
    is_deeply $s2, $schema, "reserialized identically";
}

## Fixed
{
    my $s = <<EOJ;
{ "type": "fixed", "name": "somefixed", "size": "something" }
EOJ
    throws_ok { Avro::Schema->parse($s) } "Avro::Schema::Error::Parse",
        "size must be an int";

    $s = <<EOJ;
{ "type": "fixed", "name": "somefixed", "size": -100 }
EOJ
    throws_ok { Avro::Schema->parse($s) } "Avro::Schema::Error::Parse",
        "size must be a POSITIVE int";

    $s = <<EOJ;
{ "type": "fixed", "name": "somefixed", "size": 0 }
EOJ
    throws_ok { Avro::Schema->parse($s) } "Avro::Schema::Error::Parse",
        "size must be a POSITIVE int > 0";

    $s = <<EOJ;
{ "type": "fixed", "name": "somefixed", "size": 0.2 }
EOJ
    throws_ok { Avro::Schema->parse($s) } "Avro::Schema::Error::Parse",
        "size must be an int";

    $s = <<EOJ;
{ "type": "fixed", "name": "somefixed", "size": 5e2 }
EOJ
    my $schema = Avro::Schema->parse($s);

    is $schema->type, 'fixed', "fixed";
    is $schema->fullname, 'somefixed', "name";
    is $schema->size, 500, "size of fixed";
    my $string = $schema->to_string;
    my $s2 = Avro::Schema->parse($string);
    is_deeply $s2, $schema, "reserialized identically";
}

done_testing;
