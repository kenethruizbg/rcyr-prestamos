/*****************************************************************************
  Representación del Conocimiento y Razonamiento - UC3M, curso 2026/27
  Entregable: reglas en Visual Prolog
  Sistema basado en conocimiento para la concesión de préstamos personales

  Fabián Alejandro Gutiérrez Peña (568480)
  Sergio Mínguez Cruces (602888)
  Keneth Guillermo Ruiz Martínez (601403)

  Uso: crear un proyecto de consola en Visual Prolog y sustituir main.pro por
  este fichero (main.cl ya declara run : core::runnable).

  Estructura
    1. Dominios      -> atributos enumerados de la ontología (Protégé).
    2. Hechos        -> una relación por clase de la ontología.
    3. Cálculos      -> atributos derivados (*) de la ontología: ingresos,
                        cuota, tasa de esfuerzo, LTV, empleo estable...
    4. Reglas (20)   -> D1-D5 denegar, E1-E3 escalar, V1-V8 devolver a
                        oficina y F1-F4 decisión final por prioridad.
    5. Casos de prueba (4) y programa principal.

  Simplificaciones respecto a la ontología (acordadas al recortar reglas)
    - Un préstamo tiene un único titular (la ontología no recoge cotitulares),
      así que las reglas "todos/algunos titulares" se aplican al titular.
    - El avalista se representa como una Garantia de tipo avalPersonal; se
      supone que la oficina ya ha comprobado que es válido.
    - edad y vigente son atributos derivados en la ontología (de
      fechaNacimiento y fechaEmision); aquí se dan ya calculados.
    - tipoContrato añade el valor sinContrato para representar el desempleo,
      que la ontología no tenía.
    - Quedan fuera por no tener atributos en la ontología: fallido, riesgo
      reputacional, riesgo país, sector sensible, alquiler, pensión
      alimentaria, bonus, precio de compra y ubicación de la garantía.
*****************************************************************************/

implement main
    open core

/*---------------------------------------------------------------------------
  1. DOMINIOS (valores de los atributos enumerados de la ontología)
---------------------------------------------------------------------------*/
domains
    tipoPrestamo = hipotecario; personalConsumo.
    finalidad = compraPrimeraVivienda; compraOtraVivienda; consumoGeneral; estudios; reforma; vehiculo.
    tipoGarantia = avalPersonal; hipotecaria; pignoracionSaldos.
    tipoContrato = indefinido; funcionario; temporal; fijoDiscontinuo; sinContrato.
    regimenCotizacion = regimenGeneral; regimenAutonomos.
    tipoDocumento = dni; pasaporte; tie.
    nombreFichero = asnef; experian.
    nivelRiesgo = bajo; medio; alto.
    resultado = aprobar; denegar; devolverAOficina; escalar.

constants
    mayoriaEdad : integer = 18.
    smiMensual : real = 1381.33. % SMI 2025: 16.576 EUR/año entre 12 meses
    umbralMoraRelevante : real = 1000.0. % EUR de importe dudoso en CIRBE
    limiteEdadMasPlazo : real = 80.0.
    plazoConsumoOrdinario : real = 8.0. % años; de 8 a 10 es tramo excepcional
    plazoConsumoExcepcional : real = 10.0.

/*---------------------------------------------------------------------------
  2. HECHOS (una relación por clase de la ontología)
---------------------------------------------------------------------------*/
class facts - baseDeHechos
    % Prestatario(nombre, edad*, esResidente, esClienteEntidad, cuotasDeudasActuales)
    prestatario : (string IdTitular, string Nombre, integer Edad, boolean EsResidente, boolean EsClienteEntidad,
        real CuotasDeudasActuales).
    % Prestatario solicita Prestamo(numeroExpediente, importe, plazo, tipoInteres, tipoPrestamo, finalidad)
    prestamo : (string Expediente, string IdTitular, real Importe, real PlazoAnios, real TipoInteresAnual,
        tipoPrestamo TipoPrestamo, finalidad Finalidad).
    % Prestamo tieneGarantia Garantia(tipoGarantia, valorGarantia, esPrimeraVivienda)
    garantia : (string Expediente, tipoGarantia TipoGarantia, real ValorGarantia, boolean EsPrimeraVivienda).
    % Prestamista(nombrePrestamista, importeMaximoAutorizado, plazoMaximoAutorizado)
    prestamista : (string Nombre, real ImporteMaximoAutorizado, real PlazoMaximoAutorizado).
    % Subclases de Documentacion que aporta el prestatario (vigente*)
    documentoIdentidad : (string IdTitular, tipoDocumento TipoDocumento, boolean Vigente).
    cirbe : (string IdTitular, real DeudaVivaTotal, real ImporteDudoso, boolean Vigente).
    nomina : (string IdTitular, real SalarioNetoMensual, integer NumPagasAnuales, boolean Vigente).
    irpf : (string IdTitular, real RendimientosNetosTrabajo, boolean Vigente).
    vidaLaboral : (string IdTitular, tipoContrato TipoContrato, real AntiguedadAnios, regimenCotizacion Regimen,
        boolean Vigente).
    % Prestatario apareceEn FicheroNegativo(nombreFichero, importeImpagado, deudaSaldada)
    ficheroNegativo : (string IdTitular, nombreFichero Fichero, real ImporteImpagado, boolean DeudaSaldada).

/*---------------------------------------------------------------------------
  3. CÁLCULOS PREVIOS (atributos derivados; no son reglas de decisión)
---------------------------------------------------------------------------*/
class predicates
    titularDe : (string Expediente, string IdTitular [out]) determ.
    ingresosMensuales : (string IdTitular, real Ingresos [out]) determ.
    cuotaMensual : (string Expediente, real Cuota [out]) determ.
    tasaEsfuerzo : (string Expediente, real Tasa [out]) determ.
    nivelRiesgoTasa : (real Tasa) -> nivelRiesgo Nivel.
    loanToValue : (string Expediente, real LTV [out], real Limite [out]) determ.
    limiteLTV : (boolean EsPrimeraVivienda) -> real Limite.
    plazoMaximo : (tipoPrestamo TipoPrestamo, finalidad Finalidad) -> real PlazoMaximoAnios.
    empleoEstable : (string IdTitular) determ.
    estableSegunContrato : (tipoContrato TipoContrato, real AntiguedadAnios) determ.
    tieneAvalista : (string Expediente) determ.
    tieneRefuerzo : (string Expediente) determ.
    tieneImpagoDeBajoPeso : (string IdTitular) determ.
    documentoFaltante : (string IdTitular, string Documento [out]) nondeterm.

clauses
    titularDe(Expediente, IdTitular) :-
        prestamo(Expediente, IdTitular, _, _, _, _, _),
        !.

    % Ingreso computable: nómina prorrateada a 12 meses; si no hay nómina
    % (autónomo), los rendimientos del IRPF entre 12. El bonus no cuenta.
    ingresosMensuales(IdTitular, Ingresos) :-
        nomina(IdTitular, SalarioNeto, NumPagas, _),
        !,
        Ingresos = SalarioNeto * NumPagas / 12.
    ingresosMensuales(IdTitular, Ingresos) :-
        irpf(IdTitular, Rendimientos, _),
        !,
        Ingresos = Rendimientos / 12.

    % Cuota mensual con el sistema francés (cuota constante).
    cuotaMensual(Expediente, Cuota) :-
        prestamo(Expediente, _, Importe, PlazoAnios, InteresAnual, _, _),
        !,
        NumCuotas = PlazoAnios * 12,
        InteresMensual = InteresAnual / 100 / 12,
        if InteresMensual > 0 then
            Cuota = Importe * InteresMensual / (1 - (1 + InteresMensual) ^ (-NumCuotas))
        else
            Cuota = Importe / NumCuotas
        end if.

    % Tasa de esfuerzo = (cuota nueva + cuotas de deudas vigentes) / ingresos.
    tasaEsfuerzo(Expediente, Tasa) :-
        titularDe(Expediente, IdTitular),
        prestatario(IdTitular, _, _, _, _, CuotasActuales),
        !,
        ingresosMensuales(IdTitular, Ingresos),
        Ingresos > 0,
        cuotaMensual(Expediente, Cuota),
        Tasa = (Cuota + CuotasActuales) / Ingresos.

    % nivelRiesgo (borroso) del FactorRiesgo TasaEsfuerzo.
    nivelRiesgoTasa(Tasa) = bajo :-
        Tasa < 0.40,
        !.
    nivelRiesgoTasa(Tasa) = medio :-
        Tasa <= 0.60,
        !.
    nivelRiesgoTasa(_) = alto.

    % LTV = importe / valor de la garantía. Solo con garantía hipotecaria.
    loanToValue(Expediente, LTV, Limite) :-
        garantia(Expediente, hipotecaria, ValorGarantia, EsPrimeraVivienda),
        ValorGarantia > 0,
        prestamo(Expediente, _, Importe, _, _, _, _),
        !,
        LTV = Importe / ValorGarantia,
        Limite = limiteLTV(EsPrimeraVivienda).

    limiteLTV(true) = 0.80 :-
        !.
    limiteLTV(_) = 0.70.

    % Plazo máximo según tipo y finalidad. En consumo el tope real es 10 años
    % porque de 8 a 10 se escala (E3) en lugar de devolver.
    plazoMaximo(hipotecario, _) = 30.0 :-
        !.
    plazoMaximo(_, vehiculo) = 5.0 :-
        !.
    plazoMaximo(_, _) = plazoConsumoExcepcional.

    % Empleo estable: indefinido o funcionario con >= 2 años de antigüedad,
    % o temporal / fijo discontinuo con >= 3 años.
    empleoEstable(IdTitular) :-
        vidaLaboral(IdTitular, TipoContrato, Antiguedad, _, _),
        estableSegunContrato(TipoContrato, Antiguedad),
        !.

    estableSegunContrato(indefinido, Antiguedad) :-
        Antiguedad >= 2.
    estableSegunContrato(funcionario, Antiguedad) :-
        Antiguedad >= 2.
    estableSegunContrato(temporal, Antiguedad) :-
        Antiguedad >= 3.
    estableSegunContrato(fijoDiscontinuo, Antiguedad) :-
        Antiguedad >= 3.

    tieneAvalista(Expediente) :-
        garantia(Expediente, avalPersonal, _, _),
        !.

    % Refuerzo: avalista, pignoración de saldos o garantía hipotecaria.
    tieneRefuerzo(Expediente) :-
        garantia(Expediente, _, _, _),
        !.

    % Impago de bajo peso: aparece en ASNEF/Experian con deuda sin saldar
    % (suministros, financieras) o tiene un importe dudoso pequeño en CIRBE.
    tieneImpagoDeBajoPeso(IdTitular) :-
        ficheroNegativo(IdTitular, _, _, false),
        !.
    tieneImpagoDeBajoPeso(IdTitular) :-
        cirbe(IdTitular, _, ImporteDudoso, _),
        ImporteDudoso > 0,
        ImporteDudoso <= umbralMoraRelevante,
        !.

    % Documentación exigida: identidad, CIRBE y vida laboral siempre; además
    % nómina (régimen general) o IRPF (autónomos). Debe estar vigente.
    documentoFaltante(IdTitular, "documento de identidad") :-
        not(documentoIdentidad(IdTitular, _, true)).
    documentoFaltante(IdTitular, "CIRBE") :-
        not(cirbe(IdTitular, _, _, true)).
    documentoFaltante(IdTitular, "vida laboral") :-
        not(vidaLaboral(IdTitular, _, _, _, true)).
    documentoFaltante(IdTitular, "nómina") :-
        vidaLaboral(IdTitular, _, _, regimenGeneral, _),
        not(nomina(IdTitular, _, _, true)).
    documentoFaltante(IdTitular, "IRPF") :-
        vidaLaboral(IdTitular, _, _, regimenAutonomos, _),
        not(irpf(IdTitular, _, true)).

/*---------------------------------------------------------------------------
  4. REGLAS DE DECISIÓN (20)
     Cada cláusula de denegacion/escalado/devolucion es una regla. No llevan
     corte para que se evalúen todas y se acumulen todos los motivos.
---------------------------------------------------------------------------*/
class predicates
    denegacion : (string Expediente, string Motivo [out]) nondeterm.
    escalado : (string Expediente, string Motivo [out]) nondeterm.
    devolucion : (string Expediente, string Motivo [out]) nondeterm.
    decidir : (string Expediente, resultado Resultado [out], string* Motivos [out]).

clauses
    /* ---- Denegar ---- */

    % D1. El titular es menor de edad.
    denegacion(Expediente, "D1: el titular es menor de edad") :-
        titularDe(Expediente, IdTitular),
        prestatario(IdTitular, _, Edad, _, _, _),
        Edad < mayoriaEdad.

    % D2. El titular está en desempleo.
    denegacion(Expediente, "D2: el titular está en desempleo") :-
        titularDe(Expediente, IdTitular),
        vidaLaboral(IdTitular, sinContrato, _, _, _).

    % D3. El titular cobra menos que el SMI (tiempo parcial).
    denegacion(Expediente, Motivo) :-
        titularDe(Expediente, IdTitular),
        ingresosMensuales(IdTitular, Ingresos),
        Ingresos > 0,
        Ingresos < smiMensual,
        Motivo = string::format("D3: ingresos de % EUR/mes, por debajo del SMI", fmt(Ingresos)).

    % D4. El titular tiene mora relevante en CIRBE (más de 1.000 EUR).
    denegacion(Expediente, Motivo) :-
        titularDe(Expediente, IdTitular),
        cirbe(IdTitular, _, ImporteDudoso, _),
        ImporteDudoso > umbralMoraRelevante,
        Motivo = string::format("D4: mora en CIRBE de % EUR (más de 1.000 EUR)", fmt(ImporteDudoso)).

    % D5. La tasa de esfuerzo supera el 60 % (nivel de riesgo alto).
    denegacion(Expediente, Motivo) :-
        tasaEsfuerzo(Expediente, Tasa),
        alto = nivelRiesgoTasa(Tasa),
        Motivo = string::format("D5: tasa de esfuerzo de % (supera 0.60)", fmt(Tasa)).

    /* ---- Escalar a un analista superior ---- */

    % E1. El importe supera el límite autorizado del prestamista.
    escalado(Expediente, Motivo) :-
        prestamo(Expediente, _, Importe, _, _, _, _),
        prestamista(_, ImporteMaximo, _),
        Importe > ImporteMaximo,
        Motivo = string::format("E1: importe de % EUR supera el máximo autorizado (% EUR)", fmt(Importe), fmt(ImporteMaximo)).

    % E2. El plazo supera el límite autorizado del prestamista.
    escalado(Expediente, Motivo) :-
        prestamo(Expediente, _, _, Plazo, _, _, _),
        prestamista(_, _, PlazoMaximo),
        Plazo > PlazoMaximo,
        Motivo = string::format("E2: plazo de % años supera el máximo autorizado (% años)", Plazo, PlazoMaximo).

    % E3. Préstamo de consumo en el tramo excepcional de 8 a 10 años.
    escalado(Expediente, Motivo) :-
        prestamo(Expediente, _, _, Plazo, _, personalConsumo, _),
        Plazo > plazoConsumoOrdinario,
        Plazo <= plazoConsumoExcepcional,
        Motivo = string::format("E3: consumo a % años, tramo excepcional de 8 a 10 años", Plazo).

    /* ---- Devolver a la oficina (con la condición que se propone) ---- */

    % V1. Falta documentación o no está vigente.
    devolucion(Expediente, Motivo) :-
        titularDe(Expediente, IdTitular),
        Faltan = [ Documento || documentoFaltante(IdTitular, Documento) ],
        Faltan <> [],
        Motivo = string::format("V1: falta documentación o no está vigente: %", string::concatWithDelimiter(Faltan, ", ")).

    % V2. Impagos de bajo peso: se pide aclaración en lugar de denegar.
    devolucion(Expediente, "V2: impagos de bajo peso en ficheros negativos. Pedir aclaración al cliente") :-
        titularDe(Expediente, IdTitular),
        tieneImpagoDeBajoPeso(IdTitular).

    % V3. Edad + plazo >= 80 sin avalista ni garantía.
    devolucion(Expediente, Motivo) :-
        prestamo(Expediente, IdTitular, _, Plazo, _, _, _),
        prestatario(IdTitular, _, Edad, _, _, _),
        Edad + Plazo >= limiteEdadMasPlazo,
        not(tieneRefuerzo(Expediente)),
        Motivo = string::format("V3: edad + plazo = % (>= 80). Condición: exigirAvalista o pignorarSaldos", Edad + Plazo).

    % V4. El titular no tiene empleo estable y no hay avalista.
    devolucion(Expediente, "V4: el titular no tiene empleo estable. Condición: exigirAvalista") :-
        titularDe(Expediente, IdTitular),
        not(empleoEstable(IdTitular)),
        not(vidaLaboral(IdTitular, sinContrato, _, _, _)), % el desempleo ya lo deniega D2
        not(tieneAvalista(Expediente)).

    % V5. Tasa de esfuerzo entre 40 % y 60 % (riesgo medio) sin avalista.
    devolucion(Expediente, Motivo) :-
        tasaEsfuerzo(Expediente, Tasa),
        medio = nivelRiesgoTasa(Tasa),
        not(tieneAvalista(Expediente)),
        Motivo = string::format("V5: tasa de esfuerzo de % (entre 0.40 y 0.60). Condición: exigirAvalista", fmt(Tasa)).

    % V6. El titular no es residente y no hay avalista ni garantía.
    devolucion(Expediente, "V6: el titular no es residente. Condición: exigirAvalista o pignorarSaldos") :-
        titularDe(Expediente, IdTitular),
        prestatario(IdTitular, _, _, false, _, _),
        not(tieneRefuerzo(Expediente)).

    % V7. El plazo supera el máximo para su tipo y finalidad.
    devolucion(Expediente, Motivo) :-
        prestamo(Expediente, _, _, Plazo, _, TipoPrestamo, Finalidad),
        Maximo = plazoMaximo(TipoPrestamo, Finalidad),
        Plazo > Maximo,
        Motivo = string::format("V7: plazo de % años supera el máximo de % para %. Condición: reducir plazo", Plazo, Maximo, Finalidad).

    % V8. El LTV supera el límite (80 % primera vivienda, 70 % segunda).
    devolucion(Expediente, Motivo) :-
        loanToValue(Expediente, LTV, Limite),
        LTV > Limite,
        Motivo = string::format("V8: LTV de % supera el límite de %. Condición: reducirImporte", fmt(LTV), fmt(Limite)).

    /* ---- Decisión final, por orden de prioridad ---- */

    % F1. Si hay alguna denegación, se deniega.
    decidir(Expediente, denegar, Motivos) :-
        Motivos = [ Motivo || denegacion(Expediente, Motivo) ],
        Motivos <> [],
        !.
    % F2. Si no, si hay alguna devolución, se devuelve a la oficina.
    decidir(Expediente, devolverAOficina, Motivos) :-
        Motivos = [ Motivo || devolucion(Expediente, Motivo) ],
        Motivos <> [],
        !.
    % F3. Si no, si hay algún escalado, se escala.
    decidir(Expediente, escalar, Motivos) :-
        Motivos = [ Motivo || escalado(Expediente, Motivo) ],
        Motivos <> [],
        !.
    % F4. Si no se cumple ninguna de las anteriores, se aprueba.
    decidir(_, aprobar, ["cumple todos los criterios del sistema"]).

/*---------------------------------------------------------------------------
  5. CASOS DE PRUEBA
     Un solo prestamista para todos los expedientes.
     Resultado esperado de cada caso en su comentario.
---------------------------------------------------------------------------*/
clauses
    prestamista("Analista de riesgos nivel 1", 250000.0, 30.0).

    % Caso 1 - Ana. Consumo de 15.000 EUR a 5 años, indefinida con 6 años de
    % antigüedad, sin deudas. Cuota 297,02; tasa 0,12 (bajo).
    % Esperado: APROBAR.
    prestatario("T1", "Ana López", 35, true, true, 0.0).
    prestamo("EXP-001", "T1", 15000.0, 5.0, 7.0, personalConsumo, consumoGeneral).
    documentoIdentidad("T1", dni, true).
    cirbe("T1", 0.0, 0.0, true).
    vidaLaboral("T1", indefinido, 6.0, regimenGeneral, true).
    nomina("T1", 2200.0, 14, true).

    % Caso 2 - Luis. Vehículo de 12.000 EUR a 4 años, con 3.500 EUR de mora en
    % CIRBE y un recibo pequeño en ASNEF. Cuota 292,96; tasa 0,24 (bajo).
    % Esperado: DENEGAR por D4 (la denegación tiene prioridad sobre V2).
    prestatario("T2", "Luis Martín", 41, true, true, 250.0).
    prestamo("EXP-002", "T2", 12000.0, 4.0, 8.0, personalConsumo, vehiculo).
    documentoIdentidad("T2", dni, true).
    cirbe("T2", 20000.0, 3500.0, true).
    vidaLaboral("T2", indefinido, 4.0, regimenGeneral, true).
    nomina("T2", 1900.0, 14, true).
    ficheroNegativo("T2", asnef, 120.0, false).

    % Caso 3 - Marta. Hipoteca de 200.000 EUR a 30 años para primera vivienda
    % tasada en 230.000 EUR, contrato temporal de 1,5 años. Cuota 843,21;
    % tasa 0,33 (bajo); LTV 0,87 > 0,80. Edad + plazo = 82, pero la garantía
    % hipotecaria sirve de refuerzo, así que V3 no salta.
    % Esperado: DEVOLVER A OFICINA por V4 (empleo) y V8 (LTV).
    prestatario("T3", "Marta Ruiz", 52, true, true, 300.0).
    prestamo("EXP-003", "T3", 200000.0, 30.0, 3.0, hipotecario, compraPrimeraVivienda).
    garantia("EXP-003", hipotecaria, 230000.0, true).
    documentoIdentidad("T3", dni, true).
    cirbe("T3", 0.0, 0.0, true).
    vidaLaboral("T3", temporal, 1.5, regimenGeneral, true).
    nomina("T3", 3000.0, 14, true).

    % Caso 4 - Pedro. Consumo de 30.000 EUR a 9 años para una reforma,
    % funcionario con 10 años. Cuota 360,17; tasa 0,13 (bajo).
    % Esperado: ESCALAR por E3 (tramo excepcional de 8 a 10 años).
    prestatario("T4", "Pedro Gómez", 38, true, true, 0.0).
    prestamo("EXP-004", "T4", 30000.0, 9.0, 6.0, personalConsumo, reforma).
    documentoIdentidad("T4", dni, true).
    cirbe("T4", 0.0, 0.0, true).
    vidaLaboral("T4", funcionario, 10.0, regimenGeneral, true).
    nomina("T4", 2800.0, 12, true).

/*---------------------------------------------------------------------------
  6. PROGRAMA PRINCIPAL: informe de cada expediente
---------------------------------------------------------------------------*/
class predicates
    informe : (string Expediente).
    fmt : (real Numero) -> string Texto.

clauses
    fmt(Numero) = string::format("%.2f", Numero).

    informe(Expediente) :-
        prestamo(Expediente, IdTitular, Importe, Plazo, Interes, TipoPrestamo, Finalidad),
        prestatario(IdTitular, Nombre, Edad, _, _, _),
        !,
        stdio::writef("\n=== % - % (% años) ===\n", Expediente, Nombre, Edad),
        stdio::writef("Préstamo % (%): % EUR a % años, interés anual %\n", TipoPrestamo, Finalidad, fmt(Importe), Plazo,
            fmt(Interes)),
        if cuotaMensual(Expediente, Cuota) then
            stdio::writef("Cuota mensual: % EUR\n", fmt(Cuota))
        end if,
        if ingresosMensuales(IdTitular, Ingresos) then
            stdio::writef("Ingresos computables: % EUR/mes\n", fmt(Ingresos))
        end if,
        if tasaEsfuerzo(Expediente, Tasa) then
            stdio::writef("Tasa de esfuerzo: % (riesgo %)\n", fmt(Tasa), nivelRiesgoTasa(Tasa))
        end if,
        if loanToValue(Expediente, LTV, Limite) then
            stdio::writef("Loan to value: % (límite %)\n", fmt(LTV), fmt(Limite))
        end if,
        decidir(Expediente, Resultado, Motivos),
        stdio::writef("DECISIÓN: %\n", Resultado),
        foreach Motivo = list::getMember_nd(Motivos) do
            stdio::writef("  - %\n", Motivo)
        end foreach.
    informe(Expediente) :-
        stdio::writef("\n=== % ===\nFaltan los datos del préstamo o del titular.\n", Expediente).

    run() :-
        stdio::write("Sistema de concesión de préstamos personales\n"),
        foreach prestamo(Expediente, _, _, _, _, _, _) do
            informe(Expediente)
        end foreach,
        stdio::write("\nPulsa Enter para salir."),
        _ = stdio::readLine().

end implement main

goal
    console::runUtf8(main::run).
