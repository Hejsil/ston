# `ston` - Streaming Text Object Notation

A simple text format for streaming objects in a line based format.

## Grammar
```
Lines <- Line*
Line <- Suffix* '=' VALUE '\n'

Suffix
   <- '.' FIELD
    / '[' INDEX ']'

INDEX <- [^]\n]*
FIELD <- [^=.\[\n]*
VALUE <- [^\n]*
```


## Examples (json vs ston)

```json
{
    "bool": true,
    "int": 2,
    "float": 1.1,
    "string": "string",
    "array": [ 1, 2, 3 ],
    "nest": {
        "int": 2,
        "string": "string"
    }
}
```

```
.bool=true
.int=2
.float=1.1
.string=string
.array[0]=1
.array[1]=2
.array[2]=3
.nest.int=2
.nest.string=string
```
