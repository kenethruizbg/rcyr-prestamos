# RCyR: reglas en Visual Prolog

Sistema basado en conocimiento para la concesión de préstamos personales. Es el entregable de reglas de Representación del Conocimiento y Razonamiento (UC3M, curso 2026/27). Se entrega el 28 de octubre de 2026.

## Cómo probarlo

Compila sin errores con Visual Prolog 11 (build 1112) y los 4 casos de prueba dan el resultado esperado.

- **En Windows:** abrid `rcyr.vipprj` con Visual Prolog y ejecutadlo (Build › Execute). Las reglas están en `main.pro`; el resto son los ficheros del proyecto de consola.
- **Sin Windows:** cada push compila y ejecuta el programa en GitHub Actions ([pestaña Actions](../../actions)). La salida sale en el paso "Ejecutar los casos de prueba" y se puede descargar con el `.exe` desde el artefacto `salida`.

Resultados esperados: Ana se aprueba, Luis se deniega (D4), Marta se devuelve a la oficina (V4 y V8) y Pedro se escala (E3).

El compilador da 5 avisos que no son errores. 4 son valores de la ontología que ningún caso de prueba usa (`pignoracionSaldos`, `pasaporte`, `tie`, `experian`). El quinto es que ningún caso usa `irpf`, porque no hay ningún autónomo.

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
