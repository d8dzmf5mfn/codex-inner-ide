import type { CompletionItemKind } from "./languages";

export type CatalogCompletion = Readonly<{
  label: string;
  insertText: string;
  detail: string;
  kind: CompletionItemKind;
  snippet?: boolean;
}>;

const names = (values: string, detail: string, kind: CompletionItemKind = "property"): CatalogCompletion[] =>
  values.trim().split(/\s+/).map((label) => ({ label, insertText: label, detail, kind }));

const calls = (values: string, detail: string): CatalogCompletion[] =>
  values.trim().split(/\s+/).map((label) => ({
    label,
    insertText: `${label}(${"${1}"})`,
    detail,
    kind: "function",
    snippet: true
  }));

export const CORE_COMPLETION_CATALOGS: Record<string, readonly CatalogCompletion[]> = {
  python: [
    ...calls(`
      abs aiter all anext any ascii bin bool breakpoint bytearray bytes callable chr classmethod compile complex
      delattr dict dir divmod enumerate eval exec filter float format frozenset getattr globals hasattr hash help hex
      id input int isinstance issubclass iter len list locals map max memoryview min next object oct open ord pow print
      property range repr reversed round set setattr slice sorted staticmethod str sum super tuple type vars zip __import__
    `, "Python built-in"),
    ...names(`
      BaseException BaseExceptionGroup Exception ExceptionGroup ArithmeticError AssertionError AttributeError
      BlockingIOError BrokenPipeError BufferError BytesWarning ChildProcessError ConnectionAbortedError ConnectionError
      ConnectionRefusedError ConnectionResetError DeprecationWarning EOFError EncodingWarning EnvironmentError
      FileExistsError FileNotFoundError FloatingPointError FutureWarning GeneratorExit ImportError ImportWarning
      IndentationError IndexError InterruptedError IsADirectoryError KeyError KeyboardInterrupt LookupError MemoryError
      ModuleNotFoundError NameError NotADirectoryError NotImplementedError OSError OverflowError PendingDeprecationWarning
      PermissionError ProcessLookupError RecursionError ReferenceError ResourceWarning RuntimeError RuntimeWarning
      StopAsyncIteration StopIteration SyntaxError SyntaxWarning SystemError SystemExit TabError TimeoutError TypeError
      UnboundLocalError UnicodeDecodeError UnicodeEncodeError UnicodeError UnicodeTranslateError UnicodeWarning UserWarning
      ValueError Warning ZeroDivisionError
    `, "Python built-in exception", "class"),
    ...calls("run create_task gather shield sleep wait wait_for to_thread", "asyncio"),
    ...names("Task TaskGroup Future Queue Lock Event Semaphore", "asyncio", "class"),
    ...names("Path PurePath PurePosixPath PureWindowsPath PosixPath WindowsPath", "pathlib", "class"),
    ...calls("dataclass field fields asdict astuple replace make_dataclass", "dataclasses"),
    ...names(`
      Any Annotated Callable ClassVar Concatenate Final ForwardRef Generic Iterable Iterator Literal Mapping MutableMapping
      NamedTuple Never NewType NoReturn NotRequired Optional ParamSpec Protocol Required Self Sequence TypeAlias TypeGuard
      TypeVar TypedDict Union
    `, "typing", "class"),
    ...calls("cast get_args get_origin get_type_hints is_typeddict overload runtime_checkable", "typing"),
    ...names("Counter ChainMap OrderedDict defaultdict deque", "collections", "class"),
    ...calls("namedtuple cache cached_property cmp_to_key lru_cache partial partialmethod reduce singledispatch total_ordering wraps", "collections / functools"),
    ...calls("chain combinations combinations_with_replacement compress count cycle dropwhile filterfalse groupby islice pairwise permutations product repeat starmap takewhile tee zip_longest", "itertools"),
    ...names("Future Executor ThreadPoolExecutor ProcessPoolExecutor", "concurrent.futures", "class"),
    ...calls("as_completed wait", "concurrent.futures"),
    ...names("Process Pool Queue Pipe Lock Manager Value Array", "multiprocessing", "class"),
    ...names("Queue LifoQueue PriorityQueue SimpleQueue Empty Full", "queue", "class"),
    ...names("PrettyPrinter", "pprint", "class"),
    ...calls("pprint pformat pp saferepr isreadable isrecursive", "pprint"),
    ...calls("ceil comb copysign fabs factorial floor fmod frexp fsum gcd isclose isfinite isinf isnan isqrt lcm ldexp modf perm prod remainder trunc", "math"),
    ...names("e inf nan pi tau", "math", "property"),
    ...calls("basicConfig getLogger debug info warning error exception critical", "logging"),
    ...calls("dump dumps load loads", "json"),
    ...names("JSONDecoder JSONEncoder JSONDecodeError", "json", "class"),
    ...calls("compile escape findall finditer fullmatch match search split sub subn", "re"),
    ...names("Pattern Match RegexFlag", "re", "class"),
    ...calls("run call check_call check_output getoutput", "subprocess"),
    ...names("Popen CompletedProcess CalledProcessError TimeoutExpired PIPE STDOUT DEVNULL", "subprocess", "class"),
    ...calls("getenv getcwd listdir makedirs remove rename replace walk", "os"),
    ...names("environ path sep linesep", "os", "property"),
    ...names("argv path version_info stdin stdout stderr", "sys", "property"),
    ...calls("exit getsizeof", "sys"),
    ...names("date datetime time timedelta timezone", "datetime", "class"),
    ...calls("uuid1 uuid3 uuid4 uuid5", "uuid"),
    ...names("UUID", "uuid", "class"),
    ...calls("choice choices randint randrange random sample seed shuffle uniform", "random"),
    ...calls("mean fmean geometric_mean harmonic_mean median median_grouped median_high median_low mode multimode pstdev pvariance stdev variance", "statistics")
  ],
  java: [
    ...names(`
      Object String StringBuilder StringBuffer CharSequence System Runtime Process ProcessBuilder Thread Runnable
      Class ClassLoader Package Module Math StrictMath Number Integer Long Double Float Short Byte Boolean Character
      Enum Record Throwable Exception RuntimeException Error AssertionError Optional Iterable Iterator Comparable
      AutoCloseable Cloneable Appendable
    `, "java.lang / java.util", "class"),
    ...names(`
      Collection List ArrayList LinkedList Set HashSet LinkedHashSet TreeSet Map HashMap LinkedHashMap TreeMap
      Queue Deque ArrayDeque PriorityQueue Stack Vector Arrays Collections Properties Objects UUID Scanner Random
      Spliterator StringJoiner Formatter Locale Date Calendar
    `, "java.util", "class"),
    ...names("Predicate Function Consumer Supplier BiFunction BiConsumer BinaryOperator UnaryOperator", "java.util.function", "class"),
    ...names("Stream IntStream LongStream DoubleStream Collector Collectors", "java.util.stream", "class"),
    ...names("Path Paths Files File FileInputStream FileOutputStream Reader Writer BufferedReader BufferedWriter PrintStream PrintWriter", "java.io / java.nio", "class"),
    ...names("BigDecimal BigInteger RoundingMode", "java.math", "class"),
    ...names("Instant Duration Period LocalDate LocalTime LocalDateTime ZonedDateTime ZoneId DateTimeFormatter", "java.time", "class"),
    ...names("CompletableFuture CompletionStage Executor ExecutorService Executors Future ForkJoinPool", "java.util.concurrent", "class"),
    ...names("PropertyChangeEvent PropertyChangeListener PropertyChangeSupport", "java.beans", "class"),
    ...calls("print printf println format valueOf requireNonNull compare sort copyOf asList of stream", "Common Java method")
  ],
  javascript: [
    ...names(`
      Array ArrayBuffer Atomics BigInt BigInt64Array BigUint64Array Boolean DataView Date Error EvalError
      FinalizationRegistry Float32Array Float64Array Function Infinity Int8Array Int16Array Int32Array Intl JSON Map
      Math NaN Number Object Promise Proxy RangeError ReferenceError Reflect RegExp Set SharedArrayBuffer String Symbol
      SyntaxError TypeError URIError Uint8Array Uint8ClampedArray Uint16Array Uint32Array WeakMap WeakRef WeakSet WebAssembly
    `, "JavaScript built-in", "class"),
    ...calls("decodeURI decodeURIComponent encodeURI encodeURIComponent eval isFinite isNaN parseFloat parseInt queueMicrotask structuredClone", "JavaScript global"),
    ...names(`
      AbortController AbortSignal Blob BroadcastChannel Cache Clipboard console Crypto CustomEvent document DOMParser Event
      EventSource File FileReader FormData Headers history IntersectionObserver localStorage location MutationObserver navigator
      performance prompt Request ResizeObserver Response screen sessionStorage URL URLSearchParams WebSocket window Worker
    `, "Web platform API", "class"),
    ...calls("addEventListener alert atob btoa cancelAnimationFrame clearInterval clearTimeout confirm fetch matchMedia postMessage preventDefault requestAnimationFrame setInterval setTimeout", "Web platform function"),
    ...names("Buffer process global module exports require __dirname __filename", "Node.js global", "property"),
    ...calls("setImmediate clearImmediate", "Node.js global")
  ],
  typescript: [
    ...names(`
      any bigint boolean never number object string symbol unknown void ConstructorParameters Exclude Extract InstanceType
      NonNullable Omit Parameters Partial Pick Readonly Record Required ReturnType ThisParameterType Uppercase Lowercase
      Capitalize Uncapitalize Awaited PropertyKey PromiseLike ArrayLike ReadonlyArray
    `, "TypeScript core / utility type", "class"),
    ...names("private protected public declare abstract override accessor module namespace", "TypeScript modifier", "keyword")
  ],
  html: [
    ...names(`
      a abbr address area article aside audio b base bdi bdo blockquote body br button canvas caption cite code col
      colgroup data datalist dd del details dfn dialog div dl dt em embed fieldset figcaption figure footer form h1 h2
      h3 h4 h5 h6 head header hgroup hr html i iframe img input ins kbd label legend li link main map mark menu meta
      meter nav noscript object ol optgroup option output p picture pre progress q rp rt ruby s samp script search section
      select slot small source span strong style sub summary sup table tbody td template textarea tfoot th thead time title
      tr track u ul var video wbr
    `, "HTML element", "keyword"),
    ...names(`
      accept action alt aria-label async autocomplete autofocus charset checked class content crossorigin data-* defer
      disabled download enctype for height hidden href id integrity lang loading max maxlength media method min minlength
      multiple name open pattern placeholder poster preload readonly rel required role rows selected size src srcset step
      style tabindex target title type value width
    `, "HTML attribute", "property"),
    ...names("preconnect prefetch preload prerender profile property preserveAspectRatio", "HTML metadata / SVG attribute", "property")
  ],
  css: [
    ...names(`
      accent-color align-content align-items align-self all animation animation-delay animation-direction animation-duration
      animation-fill-mode animation-iteration-count animation-name animation-play-state animation-timing-function appearance
      aspect-ratio backdrop-filter backface-visibility background background-attachment background-blend-mode background-clip
      background-color background-image background-origin background-position background-repeat background-size block-size
      border border-block border-bottom border-collapse border-color border-image border-inline border-left border-radius
      border-right border-spacing border-style border-top border-width bottom box-shadow box-sizing break-after break-before
      break-inside caption-side caret-color clear clip clip-path color color-scheme column-count column-gap column-rule
      column-span column-width columns contain container content content-visibility counter-increment counter-reset cursor
      direction display empty-cells filter flex flex-basis flex-direction flex-flow flex-grow flex-shrink flex-wrap float
      font font-family font-feature-settings font-kerning font-size font-stretch font-style font-variant font-weight gap
      grid grid-area grid-auto-columns grid-auto-flow grid-auto-rows grid-column grid-row grid-template grid-template-areas
      grid-template-columns grid-template-rows height hyphens image-rendering inline-size inset isolation justify-content
      justify-items justify-self left letter-spacing line-height list-style margin mask max-height max-width min-height
      min-width mix-blend-mode object-fit object-position opacity order outline overflow overflow-wrap overflow-x overflow-y
      overscroll-behavior padding perspective place-content place-items place-self pointer-events position print-color-adjust
      resize right rotate row-gap scale scroll-behavior scrollbar-color scrollbar-width shape-outside table-layout text-align
      text-decoration text-indent text-overflow text-shadow text-transform top touch-action transform transform-origin
      transition translate unicode-bidi user-select vertical-align visibility white-space width will-change word-break
      word-spacing writing-mode z-index
    `, "CSS property", "property"),
    ...names("active checked disabled empty enabled first-child first-of-type focus focus-visible focus-within hover invalid last-child last-of-type link not nth-child only-child placeholder-shown required root target valid visited", "CSS pseudo-class", "keyword"),
    ...names("after before first-letter first-line marker placeholder selection", "CSS pseudo-element", "keyword"),
    ...names("charset container font-face import keyframes layer media namespace page property supports", "CSS at-rule", "keyword"),
    ...names("prefers-color-scheme prefers-contrast prefers-reduced-motion", "CSS media feature", "property")
  ],
  json: [
    ...names("$schema $id $ref $defs title description type properties required additionalProperties items enum const default examples minimum maximum minLength maxLength pattern format", "JSON Schema keyword", "property")
  ],
  markdown: [
    ...names("blockquote bold bullet code emphasis heading horizontal-rule image link ordered-list strikethrough table task-list", "Markdown construct", "snippet")
  ],
  plaintext: []
};
