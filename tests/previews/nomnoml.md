# Nomnoml UML Diagrams

## Simple Association

```nomnoml
[User] -> [Service]
[Service] -> [Database]
```

## Class Diagram with Attributes

```nomnoml
[Customer|name: string;email: string|getOrders();updateProfile()]
[Order|id: int;total: float|cancel();refund()]
[Customer] 1 -> * [Order]
```

## Styled Diagram

```nomnoml
#direction: right
#spacing: 80
#padding: 12

[<abstract>Shape|area(): float]
[<actor>User]
[Shape] <:- [Circle|radius: float]
[Shape] <:- [Rectangle|width: float;height: float]
[User] -> [Shape]
```

## Associations

```nomnoml
[Pirate|eyeCount: int|attack();pillage()]
[Ship]
[Treasure]
[Pirate] fights -> [Pirate]
[Pirate] spiked -> [Pirate]
[Pirate] -> [Ship]
[Pirate] -- [Treasure]
```

## Package and Nested

```nomnoml
[<package>MVC|
  [Controller] -> [Model]
  [Controller] -> [View]
  [Model] <- [View]
]
```
