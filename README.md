# RCyR: reglas en Visual Prolog

Sistema basado en conocimiento para la concesión de préstamos personales. Es el entregable de reglas de Representación del Conocimiento y Razonamiento (UC3M, curso 2026/27). Se entrega el 28 de octubre de 2026.

## Cómo probarlo

1. En Visual Prolog (Windows), crea un proyecto nuevo de consola.
2. Sustituye el `main.pro` del proyecto por el de este repo.
3. Compila y ejecuta. Sale un informe con la decisión de cada uno de los 4 casos de prueba.

Resultados esperados: Ana se aprueba, Luis se deniega (D4), Marta se devuelve a la oficina (V4 y V8) y Pedro se escala (E3).

Todavía no se ha compilado. Si da errores, mirad primero el operador `^`, `string::concatWithDelimiter`, el formato `%.2f` y las anotaciones `[out]`.

## Las 20 reglas

| Grupo | Reglas |
|---|---|
| Denegar | D1 menor de edad · D2 desempleado · D3 ingresos < SMI · D4 mora en CIRBE > 1.000 € · D5 tasa de esfuerzo > 60 % |
| Escalar | E1 importe > límite del analista · E2 plazo > límite del analista · E3 consumo de 8 a 10 años |
| Devolver a oficina | V1 falta documentación · V2 impagos de bajo peso · V3 edad + plazo ≥ 80 sin refuerzo · V4 empleo no estable sin avalista · V5 tasa de 40 a 60 % sin avalista · V6 no residente sin refuerzo · V7 plazo > máximo por finalidad · V8 LTV > límite |
| Decisión final | F1 denegar › F2 devolver › F3 escalar › F4 aprobar |

Los cálculos previos (ingresos, cuota con el sistema francés, tasa de esfuerzo, LTV, empleo estable) son predicados auxiliares y no cuentan como reglas.

## Qué cambia respecto al documento de reglas y la ontología

- Hay un solo titular por préstamo, porque la ontología no tiene cotitulares. Por eso desaparece E6.
- Las reglas que usan datos que la ontología no tiene se han quitado: fallido, riesgo reputacional, riesgo país, sector sensible, garantía fuera de España y hipoteca sin precio de compra. Tampoco se tienen en cuenta el alquiler, la pensión alimentaria ni el bonus.
- El avalista es una `Garantia` de tipo `avalPersonal`, y se da por hecho que es válido.
- `tipoContrato` lleva un valor nuevo, `sinContrato`, para representar el desempleo.
- Había un conflicto entre V8 (consumo, máximo 8 años) y E7 (de 8 a 10 años se escala). Como devolver va antes que escalar, E7 no saltaba nunca. Ahora el tope de devolución en consumo es 10 años y el tramo de 8 a 10 se escala.
- El enumerado `condiciones` no tiene "reducir plazo" y no hay finalidad de "gastos puntuales".

Para comentar, abrid una issue o un PR.
