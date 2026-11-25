import Formula
import GridCore
import XCTest

@testable import Calc

/// Formulas typed into Excel 16.115 for Mac by script on Nov 20 2026, with Excel's answers, for the
/// 1.7 batch 7 securities, CONVERT, complex and Bessel functions. Formula cells among the data hold what Excel calculated for them.
final class ExcelBatch7Tests: XCTestCase {
  private let cells: [String: CellValue] = [
    "Data!A1": .number(0.05),
    "Data!A2": .number(0.04),
    "Data!A3": .number(0.03),
    "Data!B1": .string("3+4i"),
    "Data!B2": .string("1-2i"),
    "Data!B3": .string("2j"),
  ]
  private let formulaCells: [String: String] = [:]
  private let hiddenRows: Set<String> = []
  private let sheets = ["Data"]
  private let names: [String: String] = [:]

  private func value(_ formula: String) throws -> CellValue {
    var evaluator = FormulaEvaluator { [self] ref in self.read(ref) }
    evaluator.formulaSheetName = sheets[0]
    evaluator.sheetNames = { [sheets] in sheets }
    evaluator.formulaText = { [formulaCells] sheet, address in
      formulaCells["\(sheet)!\(address.a1)"]
    }
    evaluator.holdsFormula = { [formulaCells] sheet, address in
      formulaCells["\(sheet)!\(address.a1)"] != nil
    }
    evaluator.rowHidden = { [hiddenRows] sheet, row in hiddenRows.contains("\(sheet)!\(row)") }
    evaluator.namedRangeLookup = { [names] name in
      names.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }
        .flatMap { try? FormulaParser.parse($0.value) }
    }
    return evaluator.evaluate(try FormulaParser.parse(formula))
  }

  private func read(_ ref: FormulaRef) -> CellValue {
    let key = "\(ref.sheet ?? sheets[0])!\(ref.address.a1)"
    if let value = cells[key] { return value }
    if let formula = formulaCells[key], formula != "" {
      return (try? self.value(formula)) ?? .blank
    }
    return .blank
  }

  func testMatchesExcel() throws {
    let cases: [(String, CellValue)] = [
      ("=COUPDAYBS(DATE(2008,2,15),DATE(2017,11,15),2,0)", .number(90.0)),
      ("=COUPDAYS(DATE(2008,2,15),DATE(2017,11,15),2,0)", .number(180.0)),
      ("=COUPDAYSNC(DATE(2008,2,15),DATE(2017,11,15),2,0)", .number(90.0)),
      ("=COUPDAYBS(DATE(2024,1,31),DATE(2030,8,31),4,0)", .number(60.0)),
      ("=COUPDAYS(DATE(2024,1,31),DATE(2030,8,31),1,0)", .number(360.0)),
      ("=COUPDAYSNC(DATE(2024,1,31),DATE(2030,8,31),4,0)", .number(30.0)),
      ("=PRICE(DATE(2008,2,15),DATE(2017,11,15),0.0575,0.065,100,2,0)", .number(94.6343616213221)),
      (
        "=YIELD(DATE(2008,2,15),DATE(2017,11,15),0.0575,95.04287,100,2,0)",
        .number(0.0644096117315455)
      ),
      ("=DURATION(DATE(2008,2,15),DATE(2017,11,15),0.08,0.09,2,0)", .number(6.70449633926779)),
      ("=MDURATION(DATE(2024,1,31),DATE(2030,8,31),0.08,0.09,4,0)", .number(4.95646632057879)),
      ("=PRICE(DATE(2024,1,31),DATE(2030,8,31),0.05,0.04,100,4,0)", .number(105.761329887369)),
      ("=YIELD(DATE(2011,1,25),DATE(2011,11,15),0.06,99,100,1,0)", .number(0.0722933042630099)),
      ("=PRICE(DATE(2011,1,25),DATE(2011,11,15),0.06,0.07,100,1,0)", .number(99.175168726444)),
      ("=COUPDAYBS(DATE(2008,2,15),DATE(2017,11,15),2,1)", .number(92.0)),
      ("=COUPDAYS(DATE(2008,2,15),DATE(2017,11,15),2,1)", .number(182.0)),
      ("=COUPDAYSNC(DATE(2008,2,15),DATE(2017,11,15),2,1)", .number(90.0)),
      ("=COUPDAYBS(DATE(2024,1,31),DATE(2030,8,31),4,1)", .number(62.0)),
      ("=COUPDAYS(DATE(2024,1,31),DATE(2030,8,31),1,1)", .number(366.0)),
      ("=COUPDAYSNC(DATE(2024,1,31),DATE(2030,8,31),4,1)", .number(29.0)),
      ("=PRICE(DATE(2008,2,15),DATE(2017,11,15),0.0575,0.065,100,2,1)", .number(94.6354492078772)),
      (
        "=YIELD(DATE(2008,2,15),DATE(2017,11,15),0.0575,95.04287,100,2,1)",
        .number(0.0644110646086287)
      ),
      ("=DURATION(DATE(2008,2,15),DATE(2017,11,15),0.08,0.09,2,1)", .number(6.70174908652054)),
      ("=MDURATION(DATE(2024,1,31),DATE(2030,8,31),0.08,0.09,4,1)", .number(4.95288392090837)),
      ("=PRICE(DATE(2024,1,31),DATE(2030,8,31),0.05,0.04,100,4,1)", .number(105.758556693047)),
      ("=YIELD(DATE(2011,1,25),DATE(2011,11,15),0.06,99,100,1,1)", .number(0.0722941456334182)),
      ("=PRICE(DATE(2011,1,25),DATE(2011,11,15),0.06,0.07,100,1,1)", .number(99.1752181200781)),
      ("=COUPDAYBS(DATE(2008,2,15),DATE(2017,11,15),2,2)", .number(92.0)),
      ("=COUPDAYS(DATE(2008,2,15),DATE(2017,11,15),2,2)", .number(180.0)),
      ("=COUPDAYSNC(DATE(2008,2,15),DATE(2017,11,15),2,2)", .number(90.0)),
      ("=COUPDAYBS(DATE(2024,1,31),DATE(2030,8,31),4,2)", .number(62.0)),
      ("=COUPDAYS(DATE(2024,1,31),DATE(2030,8,31),1,2)", .number(360.0)),
      ("=COUPDAYSNC(DATE(2024,1,31),DATE(2030,8,31),4,2)", .number(29.0)),
      ("=PRICE(DATE(2008,2,15),DATE(2017,11,15),0.0575,0.065,100,2,2)", .number(94.6365640300251)),
      (
        "=YIELD(DATE(2008,2,15),DATE(2017,11,15),0.0575,95.04287,100,2,2)",
        .number(0.0644125547431392)
      ),
      ("=DURATION(DATE(2008,2,15),DATE(2017,11,15),0.08,0.09,2,2)", .number(6.69894078371224)),
      ("=MDURATION(DATE(2024,1,31),DATE(2030,8,31),0.08,0.09,4,2)", .number(4.95103301441198)),
      ("=PRICE(DATE(2024,1,31),DATE(2030,8,31),0.05,0.04,100,4,2)", .number(105.757124763809)),
      ("=YIELD(DATE(2011,1,25),DATE(2011,11,15),0.06,99,100,1,2)", .number(0.0722941456334182)),
      ("=PRICE(DATE(2011,1,25),DATE(2011,11,15),0.06,0.07,100,1,2)", .number(99.1769749011563)),
      ("=COUPDAYBS(DATE(2008,2,15),DATE(2017,11,15),2,3)", .number(92.0)),
      ("=COUPDAYS(DATE(2008,2,15),DATE(2017,11,15),2,3)", .number(182.5)),
      ("=COUPDAYSNC(DATE(2008,2,15),DATE(2017,11,15),2,3)", .number(90.0)),
      ("=COUPDAYBS(DATE(2024,1,31),DATE(2030,8,31),4,3)", .number(62.0)),
      ("=COUPDAYS(DATE(2024,1,31),DATE(2030,8,31),1,3)", .number(365.0)),
      ("=COUPDAYSNC(DATE(2024,1,31),DATE(2030,8,31),4,3)", .number(29.0)),
      ("=PRICE(DATE(2008,2,15),DATE(2017,11,15),0.0575,0.065,100,2,3)", .number(94.6351747967845)),
      (
        "=YIELD(DATE(2008,2,15),DATE(2017,11,15),0.0575,95.04287,100,2,3)",
        .number(0.0644106979507848)
      ),
      ("=DURATION(DATE(2008,2,15),DATE(2017,11,15),0.08,0.09,2,3)", .number(6.70244154474725)),
      ("=MDURATION(DATE(2024,1,31),DATE(2030,8,31),0.08,0.09,4,3)", .number(4.95334030881159)),
      ("=PRICE(DATE(2024,1,31),DATE(2030,8,31),0.05,0.04,100,4,3)", .number(105.758909864458)),
      ("=YIELD(DATE(2011,1,25),DATE(2011,11,15),0.06,99,100,1,3)", .number(0.0722941456334182)),
      ("=PRICE(DATE(2011,1,25),DATE(2011,11,15),0.06,0.07,100,1,3)", .number(99.1752181200781)),
      ("=COUPDAYBS(DATE(2008,2,15),DATE(2017,11,15),2,4)", .number(90.0)),
      ("=COUPDAYS(DATE(2008,2,15),DATE(2017,11,15),2,4)", .number(180.0)),
      ("=COUPDAYSNC(DATE(2008,2,15),DATE(2017,11,15),2,4)", .number(90.0)),
      ("=COUPDAYBS(DATE(2024,1,31),DATE(2030,8,31),4,4)", .number(60.0)),
      ("=COUPDAYS(DATE(2024,1,31),DATE(2030,8,31),1,4)", .number(360.0)),
      ("=COUPDAYSNC(DATE(2024,1,31),DATE(2030,8,31),4,4)", .number(29.0)),
      ("=PRICE(DATE(2008,2,15),DATE(2017,11,15),0.0575,0.065,100,2,4)", .number(94.6343616213221)),
      (
        "=YIELD(DATE(2008,2,15),DATE(2017,11,15),0.0575,95.04287,100,2,4)",
        .number(0.0644096117315455)
      ),
      ("=DURATION(DATE(2008,2,15),DATE(2017,11,15),0.08,0.09,2,4)", .number(6.70449633926779)),
      ("=MDURATION(DATE(2024,1,31),DATE(2030,8,31),0.08,0.09,4,4)", .number(4.95646632057879)),
      ("=PRICE(DATE(2024,1,31),DATE(2030,8,31),0.05,0.04,100,4,4)", .number(105.761329887369)),
      ("=YIELD(DATE(2011,1,25),DATE(2011,11,15),0.06,99,100,1,4)", .number(0.0722933042630099)),
      ("=PRICE(DATE(2011,1,25),DATE(2011,11,15),0.06,0.07,100,1,4)", .number(99.175168726444)),
      ("=COUPNCD(DATE(2008,2,15),DATE(2017,11,15),2,1)", .number(39583.0)),
      ("=COUPPCD(DATE(2008,2,15),DATE(2017,11,15),2,1)", .number(39401.0)),
      ("=COUPNUM(DATE(2008,2,15),DATE(2017,11,15),2,1)", .number(20.0)),
      ("=COUPNCD(DATE(2024,1,31),DATE(2030,8,31),4)", .number(45351.0)),
      ("=COUPPCD(DATE(2024,1,31),DATE(2030,8,31),4)", .number(45260.0)),
      ("=COUPNUM(DATE(2024,1,31),DATE(2030,8,31),1)", .number(7.0)),
      ("=COUPNUM(DATE(2008,2,15),DATE(2017,11,15),3)", .error(.num)),
      ("=PRICE(DATE(2008,2,15),DATE(2017,11,15),-0.01,0.05,100,2)", .error(.num)),
      ("=COUPNUM(DATE(2017,11,15),DATE(2008,2,15),2)", .error(.num)),
      (
        "=ACCRINT(DATE(2008,3,1),DATE(2008,8,31),DATE(2008,5,1),0.1,1000,2,0)",
        .number(16.6666666666667)
      ),
      (
        "=ACCRINT(DATE(2008,3,1),DATE(2008,8,31),DATE(2008,5,1),0.1,1000,2,1)",
        .number(16.5760869565217)
      ),
      ("=ACCRINTM(DATE(2008,4,1),DATE(2008,6,15),0.1,1000,3)", .number(20.5479452054795)),
      ("=ACCRINTM(DATE(2008,4,1),DATE(2008,6,15),0.1,1000)", .number(20.5555555555556)),
      ("=DISC(DATE(2018,1,25),DATE(2018,6,15),97.975,100,1)", .number(0.0524202127659577)),
      ("=INTRATE(DATE(2008,2,15),DATE(2008,5,15),1000000,1014420,2)", .number(0.05768)),
      ("=RECEIVED(DATE(2008,2,15),DATE(2008,5,15),1000000,0.0575,2)", .number(1014584.6544071)),
      ("=PRICEDISC(DATE(2008,2,16),DATE(2008,3,1),0.0525,100,2)", .number(99.7958333333333)),
      ("=YIELDDISC(DATE(2008,2,16),DATE(2008,3,1),99.795,100,2)", .number(0.0528225719868583)),
      (
        "=PRICEMAT(DATE(2008,2,15),DATE(2008,4,13),DATE(2007,11,11),0.061,0.061,0)",
        .number(99.9844988755569)
      ),
      (
        "=YIELDMAT(DATE(2008,3,15),DATE(2008,11,3),DATE(2007,11,8),0.0625,100.0123,0)",
        .number(0.0609543336915387)
      ),
      (
        "=PRICEMAT(DATE(2008,2,15),DATE(2008,4,13),DATE(2007,11,11),0.061,0.061,1)",
        .number(99.9845977645695)
      ),
      ("=TBILLPRICE(DATE(2008,3,31),DATE(2008,6,1),0.09)", .number(98.45)),
      ("=TBILLYIELD(DATE(2008,3,31),DATE(2008,6,1),98.45)", .number(0.0914169629253426)),
      ("=TBILLEQ(DATE(2008,3,31),DATE(2008,6,1),0.0914)", .number(0.094151493565943)),
      ("=TBILLEQ(DATE(2008,3,31),DATE(2008,12,1),0.0914)", .number(0.0976010329244824)),
      ("=TBILLPRICE(DATE(2008,3,31),DATE(2009,6,1),0.09)", .error(.num)),
      ("=VDB(2400,300,10,0,1)", .number(480.0)),
      ("=VDB(2400,300,120,0,1)", .number(40.0)),
      ("=VDB(2400,300,10,0,0.875,1.5)", .number(315.0)),
      ("=VDB(2400,300,10,6,10)", .number(329.1456)),
      ("=VDB(2400,300,10,3,7,2,TRUE)", .number(725.48352)),
      ("=VDB(2400,300,10,1.5,4)", .number(732.672)),
      ("=VDB(2400,300,10,6.5,9)", .number(235.0371072)),
      ("=AMORLINC(2400,DATE(2008,8,19),DATE(2008,12,31),300,1,0.15,1)", .number(360.0)),
      ("=AMORLINC(2400,DATE(2008,8,19),DATE(2008,12,31),300,0,0.15,1)", .number(131.803278688525)),
      ("=AMORLINC(2400,DATE(2008,8,19),DATE(2008,12,31),300,6,0.15,1)", .number(168.196721311475)),
      ("=AMORLINC(2400,DATE(2008,8,19),DATE(2008,12,31),300,7,0.15,1)", .number(0.0)),
      ("=AMORDEGRC(2400,DATE(2008,8,19),DATE(2008,12,31),300,1,0.15,1)", .number(776.0)),
      ("=AMORDEGRC(2400,DATE(2008,8,19),DATE(2008,12,31),300,0,0.15,1)", .number(330.0)),
      ("=AMORDEGRC(2400,DATE(2008,8,19),DATE(2008,12,31),300,3,0.15,1)", .number(303.0)),
      ("=AMORDEGRC(2400,DATE(2008,8,19),DATE(2008,12,31),300,5,0.15,1)", .number(158.0)),
      ("=AMORDEGRC(2400,DATE(2008,8,19),DATE(2008,12,31),300,6,0.15,1)", .number(0.0)),
      ("=FVSCHEDULE(1,{0.09,0.11,0.1})", .number(1.33089)),
      ("=FVSCHEDULE(100,A1:A3)", .number(112.476)),
      ("=DOLLARDE(1.02,16)", .number(1.125)),
      ("=DOLLARDE(1.1,32)", .number(1.3125)),
      ("=DOLLARFR(1.125,16)", .number(1.02)),
      ("=DOLLARFR(1.125,32)", .number(1.04)),
      ("=DOLLARDE(1.02,0)", .error(.divZero)),
      ("=DOLLARDE(-1.02,16)", .number(-1.125)),
      ("=PDURATION(0.025,2000,2200)", .number(3.85986616262266)),
      ("=RRI(96,10000,11000)", .number(0.00099330737629133)),
      ("=CONVERT(68,\"F\",\"C\")", .number(20.0)),
      ("=CONVERT(2.5,\"ft\",\"sec\")", .error(.na)),
      ("=CONVERT(6,\"tsp\",\"tbs\")", .number(2.0)),
      ("=CONVERT(6,\"gal\",\"l\")", .number(22.712470704)),
      ("=CONVERT(6,\"mi\",\"km\")", .number(9.656064)),
      ("=CONVERT(6,\"km\",\"mi\")", .number(3.728227153424)),
      ("=CONVERT(6,\"in\",\"ft\")", .number(0.5)),
      ("=CONVERT(6,\"cm\",\"in\")", .number(2.36220472440945)),
      ("=CONVERT(1,\"Gibyte\",\"Mbyte\")", .number(1073.741824)),
      ("=CONVERT(100,\"kcal\",\"kJ\")", .number(418.68)),
      ("=CONVERT(1,\"mm^2\",\"in^2\")", .number(0.0015500031000062)),
      ("=CONVERT(1,\"kK\",\"C\")", .number(726.85)),
      ("=CONVERT(30,\"kn\",\"m/s\")", .number(15.4333333333333)),
      ("=CONVERT(1,\"ha\",\"uk_acre\")", .number(2.47105381467165)),
      ("=CONVERT(1,\"lbm\",\"ozm\")", .number(16.0)),
      ("=COMPLEX(3,4)", .string("3+4i")),
      ("=COMPLEX(3,4,\"j\")", .string("3+4j")),
      ("=COMPLEX(0,1)", .string("i")),
      ("=COMPLEX(0,-1)", .string("-i")),
      ("=COMPLEX(2.5,0)", .string("2.5")),
      ("=COMPLEX(0,0)", .string("0")),
      ("=COMPLEX(1,2,\"k\")", .error(.value)),
      ("=COMPLEX(-1.5,-2.25)", .string("-1.5-2.25i")),
      ("=IMABS(\"5+12i\")", .number(13.0)),
      ("=IMAGINARY(\"3+4i\")", .number(4.0)),
      ("=IMAGINARY(\"4\")", .number(0.0)),
      ("=IMREAL(\"6-9i\")", .number(6.0)),
      ("=IMARGUMENT(\"3+4i\")", .number(0.927295218001612)),
      ("=IMARGUMENT(\"0\")", .error(.divZero)),
      ("=IMCONJUGATE(\"3+4i\")", .string("3-4i")),
      ("=IMCOS(\"1+i\")", .string("0.833730025131149-0.988897705762865i")),
      ("=IMCOSH(\"4+3i\")", .string("-27.0349456030742+3.85115333481178i")),
      ("=IMCOT(\"4+3i\")", .string("0.00490118239430447-0.999266927805902i")),
      ("=IMCSC(\"4+3i\")", .string("-0.0754898329158637+0.0648774713706355i")),
      ("=IMCSCH(\"4+3i\")", .string("-0.036275889628626-0.0051744731840194i")),
      ("=IMDIV(\"-238+240i\",\"10+24i\")", .string("5+12i")),
      ("=IMEXP(\"1+i\")", .string("1.46869393991589+2.28735528717884i")),
      ("=IMLN(\"3+4i\")", .string("1.6094379124341+0.927295218001612i")),
      ("=IMLOG10(\"3+4i\")", .string("0.698970004336019+0.402719196273373i")),
      ("=IMLOG2(\"3+4i\")", .string("2.32192809488736+1.33780421245098i")),
      ("=IMPOWER(\"2+3i\",3)", .string("-46+9.00000000000001i")),
      ("=IMPOWER(\"2+3i\",0.5)", .string("1.67414922803554+0.895977476129838i")),
      ("=IMPRODUCT(\"3+4i\",\"5-3i\")", .string("27+11i")),
      ("=IMPRODUCT(B1:B2)", .string("11-2i")),
      ("=IMSEC(\"4+3i\")", .string("-0.0652940278579471-0.0752249603027732i")),
      ("=IMSECH(\"4+3i\")", .string("-0.0362534969158689-0.00516434460775318i")),
      ("=IMSIN(\"4+3i\")", .string("-7.61923172032141-6.548120040911i")),
      ("=IMSINH(\"4+3i\")", .string("-27.0168132580039+3.85373803791938i")),
      ("=IMSQRT(\"1+i\")", .string("1.09868411346781+0.455089860562227i")),
      ("=IMSUB(\"13+4i\",\"5+3i\")", .string("8+i")),
      ("=IMSUM(\"3+4i\",\"5-3i\")", .string("8+i")),
      ("=IMSUM(B1:B2)", .string("4+2i")),
      ("=IMTAN(\"4+3i\")", .string("0.00490825806749606+1.00070953606723i")),
      ("=IMSUM(\"3+4i\",\"2j\")", .error(.value)),
      ("=IMABS(\"abc\")", .error(.num)),
      ("=IMSUM(\"1+i\",2)", .string("3+i")),
      ("=IMSQRT(\"-4\")", .string("1.22464679914735E-16+2i")),
      ("=IMDIV(\"1\",\"0\")", .error(.num)),
      ("=IMREAL(\"i\")", .number(0.0)),
      ("=IMAGINARY(\"-j\")", .number(-1.0)),
      ("=IMSUB(B3,\"j\")", .string("j")),
      ("=IMPRODUCT(\"1.5e2+2i\",\"2\")", .string("300+4i")),
      ("=BESSELJ(1.9,2)", .number(0.329925828669785)),
      ("=BESSELJ(0.5,0)", .number(0.938469807423541)),
      ("=BESSELJ(10,3)", .number(0.058379836096446)),
      ("=BESSELJ(-2,1)", .number(-0.576724807896294)),
      ("=BESSELY(2.5,1)", .number(0.145918137508313)),
      ("=BESSELY(10,0)", .number(0.0556711674309512)),
      ("=BESSELY(0.5,3)", .number(-42.0594942777845)),
      ("=BESSELI(1.5,1)", .number(0.981666428475166)),
      ("=BESSELI(5,0)", .number(27.2398718943949)),
      ("=BESSELI(-2,3)", .number(-0.212739959702736)),
      ("=BESSELK(1.5,1)", .number(0.277387803632259)),
      ("=BESSELK(0.1,0)", .number(2.42706902485802)),
      ("=BESSELK(5,4)", .number(0.0152590657809274)),
      ("=BESSELJ(1.9,2.9)", .number(0.329925828669785)),
      ("=BESSELK(-1,1)", .error(.num)),
      ("=BESSELY(1,-1)", .error(.num)),
    ]
    var failures: [String] = []
    for (formula, expected) in cases {
      let got = try value(formula)
      if case .number(let e) = expected, case .number(let g) = got,
        abs(g - e) <= max(1e-9, abs(e) * 1e-9)
      {
        continue
      }
      // Excel's Bessel values are good to five or six digits (BESSELJ(10,3) is off by 8e-6 of
      // itself); Spark Grid's come from the C library and are good to fifteen.
      if formula.contains("BESSEL"), case .number(let e) = expected, case .number(let g) = got,
        abs(g - e) <= max(1e-9, abs(e) * 2e-5)
      {
        continue
      }
      // Complex numbers as text can differ in the fifteenth digit; compare them as numbers.
      if case .string(let e) = expected, case .string(let g) = got, e != g,
        let a = FormulaEvaluator.parseComplex(e), let b = FormulaEvaluator.parseComplex(g),
        abs(a.re - b.re) <= max(1e-12, abs(a.re) * 1e-12),
        abs(a.im - b.im) <= max(1e-12, abs(a.im) * 1e-12)
      {
        continue
      }
      if got != expected { failures.append("\(formula): got \(got), Excel \(expected)") }
    }
    XCTAssert(failures.isEmpty, failures.joined(separator: "\n"))
  }
}
