/*****************************************************************************
  Representación del Conocimiento y Razonamiento - UC3M, curso 2026/27
  Entregable: reglas en Visual Prolog
  Sistema basado en conocimiento para la concesión de préstamos personales

  Fabián Alejandro Gutiérrez Peña (568480)
  Sergio Mínguez Cruces (602888)
  Keneth Guillermo Ruiz Martínez (601403)

  Estructura
    1. Dominios      -> atributos enumerados de la ontología (Protégé).
    2. Hechos        -> una relación por clase de la ontología.
    3. Cálculos      -> atributos derivados (*) de la ontología: ingresos,
                        cuota, tasa de esfuerzo, LTV, empleo estable...
    4. Reglas (20)   -> D1-D5 denegar, E1-E3 escalar, V1-V8 devolver a
                        oficina y F1-F4 decisión final por prioridad.
    5. Casos de prueba (18, al menos uno por regla).
    6. Programa principal: pide un expediente (o Enter para todos) y escribe
       la decisión con las reglas que la justifican.
*****************************************************************************/

% Clases de la PFC que usa el programa además de las de la plantilla.
#include @"pfc\list\list.ph"
#include @"pfc\string\string.ph"

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
     Visual Prolog exige que las cláusulas de un mismo predicado estén
     juntas, así que los hechos van agrupados por relación. Hay un caso por
     regla: cada una de las 20 reglas decide al menos un expediente.

     Exp.  Titular  Situación                                   Esperado
     001   Ana      Consumo normal, todo en orden               aprobar (F4)
     002   Luis     3.500 EUR de mora en CIRBE                  denegar (D4)
     003   Marta    Hipoteca con LTV 0,87 y contrato temporal   devolver (V4, V8)
     004   Pedro    Consumo a 9 años                            escalar (E3)
     005   Hugo     17 años                                     denegar (D1)
     006   Elena    En desempleo                                denegar (D2)
     007   Jorge    Media jornada, 1.050 EUR/mes                denegar (D3)
     008   Sara     Tasa de esfuerzo 0,66                       denegar (D5)
     009   Raúl     Autónomo con la CIRBE caducada              devolver (V1)
     010   Lucía    Recibo de 300 EUR sin pagar en Experian     devolver (V2)
     011   Antonio  72 años + 8 de plazo, sin garantía          devolver (V3)
     012   Carmen   Tasa de esfuerzo 0,45 sin avalista          devolver (V5)
     013   Olivier  No residente, sin garantía                  devolver (V6)
     014   Iván     Coche a 7 años (máximo 5)                   devolver (V7)
     015   Beatriz  Hipoteca de 300.000 EUR (máximo 250.000)    escalar (E1)
     016   Daniel   Hipoteca a 28 años (máximo 25)              escalar (E2)
     017   Rosa     76 años + 5, con pignoración de saldos      aprobar (F4)
     018   Marcos   Contrato temporal, con avalista             aprobar (F4)

     Los pensionistas (Antonio, Rosa) se representan con una nómina y un
     contrato indefinido, porque un jubilado cuenta como empleo estable.
---------------------------------------------------------------------------*/
clauses
    % El analista de nivel 1 puede aprobar hasta 250.000 EUR y 25 años.
    prestamista("Analista de riesgos nivel 1", 250000.0, 25.0).

    prestatario("T01", "Ana López", 35, true, true, 0.0).
    prestatario("T02", "Luis Martín", 41, true, true, 250.0).
    prestatario("T03", "Marta Ruiz", 52, true, true, 300.0).
    prestatario("T04", "Pedro Gómez", 38, true, true, 0.0).
    prestatario("T05", "Hugo Sanz", 17, true, false, 0.0).
    prestatario("T06", "Elena Navarro", 45, true, true, 0.0).
    prestatario("T07", "Jorge Iglesias", 29, true, true, 0.0).
    prestatario("T08", "Sara Molina", 33, true, true, 900.0).
    prestatario("T09", "Raúl Ortega", 47, true, true, 0.0).
    prestatario("T10", "Lucía Castro", 31, true, true, 0.0).
    prestatario("T11", "Antonio Rubio", 72, true, true, 0.0).
    prestatario("T12", "Carmen Vidal", 39, true, true, 700.0).
    prestatario("T13", "Olivier Dubois", 36, false, true, 0.0).
    prestatario("T14", "Iván Herrera", 27, true, true, 0.0).
    prestatario("T15", "Beatriz Santos", 44, true, true, 0.0).
    prestatario("T16", "Daniel Prieto", 34, true, true, 200.0).
    prestatario("T17", "Rosa Delgado", 76, true, true, 0.0).
    prestatario("T18", "Marcos Gil", 26, true, true, 0.0).

    prestamo("EXP-001", "T01", 15000.0, 5.0, 7.0, personalConsumo, consumoGeneral).
    prestamo("EXP-002", "T02", 12000.0, 4.0, 8.0, personalConsumo, vehiculo).
    prestamo("EXP-003", "T03", 200000.0, 30.0, 3.0, hipotecario, compraPrimeraVivienda).
    prestamo("EXP-004", "T04", 30000.0, 9.0, 6.0, personalConsumo, reforma).
    prestamo("EXP-005", "T05", 6000.0, 3.0, 9.0, personalConsumo, estudios).
    prestamo("EXP-006", "T06", 8000.0, 4.0, 8.0, personalConsumo, consumoGeneral).
    prestamo("EXP-007", "T07", 5000.0, 4.0, 7.0, personalConsumo, consumoGeneral).
    prestamo("EXP-008", "T08", 25000.0, 5.0, 7.0, personalConsumo, reforma).
    prestamo("EXP-009", "T09", 18000.0, 6.0, 6.5, personalConsumo, reforma).
    prestamo("EXP-010", "T10", 9000.0, 4.0, 7.5, personalConsumo, consumoGeneral).
    prestamo("EXP-011", "T11", 15000.0, 8.0, 6.0, personalConsumo, reforma).
    prestamo("EXP-012", "T12", 20000.0, 6.0, 7.0, personalConsumo, consumoGeneral).
    prestamo("EXP-013", "T13", 10000.0, 4.0, 7.0, personalConsumo, consumoGeneral).
    prestamo("EXP-014", "T14", 22000.0, 7.0, 6.0, personalConsumo, vehiculo).
    prestamo("EXP-015", "T15", 300000.0, 25.0, 3.0, hipotecario, compraOtraVivienda).
    prestamo("EXP-016", "T16", 180000.0, 28.0, 3.2, hipotecario, compraPrimeraVivienda).
    prestamo("EXP-017", "T17", 10000.0, 5.0, 6.0, personalConsumo, consumoGeneral).
    prestamo("EXP-018", "T18", 7000.0, 4.0, 7.5, personalConsumo, consumoGeneral).

    garantia("EXP-003", hipotecaria, 230000.0, true).
    garantia("EXP-015", hipotecaria, 450000.0, false).
    garantia("EXP-016", hipotecaria, 240000.0, true).
    garantia("EXP-017", pignoracionSaldos, 15000.0, false).
    garantia("EXP-018", avalPersonal, 0.0, false).

    documentoIdentidad("T01", dni, true).
    documentoIdentidad("T02", dni, true).
    documentoIdentidad("T03", dni, true).
    documentoIdentidad("T04", dni, true).
    documentoIdentidad("T05", dni, true).
    documentoIdentidad("T06", dni, true).
    documentoIdentidad("T07", dni, true).
    documentoIdentidad("T08", dni, true).
    documentoIdentidad("T09", dni, true).
    documentoIdentidad("T10", tie, true).
    documentoIdentidad("T11", dni, true).
    documentoIdentidad("T12", dni, true).
    documentoIdentidad("T13", pasaporte, true).
    documentoIdentidad("T14", dni, true).
    documentoIdentidad("T15", dni, true).
    documentoIdentidad("T16", dni, true).
    documentoIdentidad("T17", dni, true).
    documentoIdentidad("T18", dni, true).

    cirbe("T01", 0.0, 0.0, true).
    cirbe("T02", 20000.0, 3500.0, true).
    cirbe("T03", 0.0, 0.0, true).
    cirbe("T04", 0.0, 0.0, true).
    cirbe("T05", 0.0, 0.0, true).
    cirbe("T06", 0.0, 0.0, true).
    cirbe("T07", 0.0, 0.0, true).
    cirbe("T08", 15000.0, 0.0, true).
    cirbe("T09", 0.0, 0.0, false). % caducada
    cirbe("T10", 0.0, 0.0, true).
    cirbe("T11", 0.0, 0.0, true).
    cirbe("T12", 30000.0, 0.0, true).
    cirbe("T13", 0.0, 0.0, true).
    cirbe("T14", 0.0, 0.0, true).
    cirbe("T15", 0.0, 0.0, true).
    cirbe("T16", 0.0, 0.0, true).
    cirbe("T17", 0.0, 0.0, true).
    cirbe("T18", 0.0, 0.0, true).

    vidaLaboral("T01", indefinido, 6.0, regimenGeneral, true).
    vidaLaboral("T02", indefinido, 4.0, regimenGeneral, true).
    vidaLaboral("T03", temporal, 1.5, regimenGeneral, true).
    vidaLaboral("T04", funcionario, 10.0, regimenGeneral, true).
    vidaLaboral("T05", temporal, 1.0, regimenGeneral, true).
    vidaLaboral("T06", sinContrato, 0.0, regimenGeneral, true).
    vidaLaboral("T07", indefinido, 3.0, regimenGeneral, true).
    vidaLaboral("T08", indefinido, 5.0, regimenGeneral, true).
    vidaLaboral("T09", indefinido, 8.0, regimenAutonomos, true).
    vidaLaboral("T10", indefinido, 4.0, regimenGeneral, true).
    vidaLaboral("T11", indefinido, 40.0, regimenGeneral, true).
    vidaLaboral("T12", indefinido, 7.0, regimenGeneral, true).
    vidaLaboral("T13", indefinido, 4.0, regimenGeneral, true).
    vidaLaboral("T14", indefinido, 3.0, regimenGeneral, true).
    vidaLaboral("T15", funcionario, 15.0, regimenGeneral, true).
    vidaLaboral("T16", indefinido, 6.0, regimenGeneral, true).
    vidaLaboral("T17", indefinido, 35.0, regimenGeneral, true).
    vidaLaboral("T18", temporal, 1.0, regimenGeneral, true).

    nomina("T01", 2200.0, 14, true).
    nomina("T02", 1900.0, 14, true).
    nomina("T03", 3000.0, 14, true).
    nomina("T04", 2800.0, 12, true).
    nomina("T05", 1500.0, 14, true).
    nomina("T07", 900.0, 14, true).
    nomina("T08", 1800.0, 14, true).
    nomina("T10", 2000.0, 14, true).
    nomina("T11", 2500.0, 14, true).
    nomina("T12", 2000.0, 14, true).
    nomina("T13", 2600.0, 12, true).
    nomina("T14", 2100.0, 14, true).
    nomina("T15", 6000.0, 14, true).
    nomina("T16", 2900.0, 14, true).
    nomina("T17", 1900.0, 14, true).
    nomina("T18", 1700.0, 14, true).

    irpf("T09", 36000.0, true).

    ficheroNegativo("T02", asnef, 120.0, false).
    ficheroNegativo("T10", experian, 300.0, false).

/*---------------------------------------------------------------------------
  6. PROGRAMA PRINCIPAL
     Pide un expediente (o Enter para todos) y escribe su informe: datos
     calculados, decisión, reglas que la motivan y reglas que también se
     cumplen pero no deciden por la prioridad.
---------------------------------------------------------------------------*/
class predicates
    informe : (string Expediente).
    otraRegla : (string Expediente, resultado Resultado, string Motivo [out]) nondeterm.
    escribirLista : (string Titulo, string* Motivos).
    leerLinea : () -> string Linea.
    fmt : (real Numero) -> string Texto.

clauses
    fmt(Numero) = string::format("%.2f", Numero).

    leerLinea() = Linea :-
        try
            Linea = string::toUpperCase(string::trim(stdio::readLine()))
        catch _ do
            Linea = ""
        end try.

    % Reglas de las otras categorías que también se cumplen.
    otraRegla(Expediente, Resultado, Motivo) :-
        Resultado <> devolverAOficina,
        devolucion(Expediente, Motivo).
    otraRegla(Expediente, Resultado, Motivo) :-
        Resultado <> escalar,
        escalado(Expediente, Motivo).

    escribirLista(_, []) :-
        !.
    escribirLista(Titulo, Motivos) :-
        stdio::writef("%\n", Titulo),
        foreach Motivo = list::getMember_nd(Motivos) do
            stdio::writef("  - %\n", Motivo)
        end foreach.

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
        escribirLista(string::format("DECISIÓN: %", Resultado), Motivos),
        Otras = [ Motivo || otraRegla(Expediente, Resultado, Motivo) ],
        escribirLista("También se cumplen (no deciden por la prioridad):", Otras).
    informe(Expediente) :-
        stdio::writef("\n=== % ===\nFaltan los datos del préstamo o del titular.\n", Expediente).

    run() :-
        stdio::write("Sistema de concesión de préstamos personales\n"),
        stdio::write("Expediente a analizar (por ejemplo EXP-003; Enter para todos): "),
        Peticion = leerLinea(),
        if Peticion = "" then
            foreach prestamo(Expediente, _, _, _, _, _, _) do
                informe(Expediente)
            end foreach
        elseif prestamo(Peticion, _, _, _, _, _, _) then
            informe(Peticion)
        else
            stdio::writef("\nNo existe el expediente %.\n", Peticion)
        end if,
        stdio::write("\nPulsa Enter para salir."),
        _ = leerLinea().

end implement main

goal
    console::runUtf8(main::run).
