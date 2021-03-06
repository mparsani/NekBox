#ifdef LIBGS
#define ASYNC
#endif

module ds

  public

  interface dssum
    module procedure dssum_dp, dssum_sp
  end interface

  interface dssum_irec
    module procedure dssum_irec_dp
  end interface

  interface dssum_isend_e
    module procedure dssum_isend_e_dp
  end interface


  interface dssum_isend
    module procedure dssum_isend_dp
  end interface

  interface dssum_wait_e
    module procedure dssum_wait_e_dp
  end interface


  interface dssum_wait
    module procedure dssum_wait_dp
  end interface

contains

!-----------------------------------------------------------------------
!> \brief setup data structures for direct stiffness operations
subroutine setupds(gs_handle,nx,ny,nz,nel,melg,vertex,glo_num)
  use kinds, only : DP, i8
  use size_m, only : nid
  use ctimer, only : dnekclock
  use parallel, only : mp=>np, nekcomm
  implicit none

  integer :: gs_handle
  integer :: vertex(1)
  integer(i8) :: glo_num(1),ngv

  real(DP) :: t0, t1
  integer :: nx, nel, ntot, ny, nz, melg
  integer, parameter :: num_ds_handles = 64
  integer, save :: handles(num_ds_handles) = -1

  ! If we've already set up it, return an existing handle
  if (nx <= num_ds_handles .and. handles(nx) >= 0) then
    gs_handle = handles(nx)
    return

  ! Make a new handle
  else

  t0 = dnekclock()

  ! Global-to-local mapping for gs
  call set_vert(glo_num,ngv,nx,nel,vertex, .FALSE. )

  ! Initialize gather-scatter code
  ntot      = nx*ny*nz*nel
#ifdef ASYNC
  call gs_setup_pick(gs_handle,glo_num,ntot,nekcomm,mp, 1)
#else
  call gs_setup(gs_handle,glo_num,ntot,nekcomm,mp)
#endif

  !   call gs_chkr(glo_num)

  t1 = dnekclock() - t0
  if (nid == 0) then
      write(6,1) t1,gs_handle,nx,ngv,melg
      1 format('   setupds time',1pe11.4,' seconds ',2i3,2i12)
  endif

  ! save the handle
  if (nx <= num_ds_handles) handles(nx) = gs_handle

  endif

  return
end subroutine setupds

!-----------------------------------------------------------------------
!> \brief Direct stiffness sum
subroutine dssum_dp(u)
  use kinds, only : DP
  use ctimer, only : ifsync, icalld, tdsmx, tdsmn, etime1, dnekclock
  use ctimer, only : tdsum, ndsum
  use input, only : ifldmhd
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  real(DP), intent(inout) :: u(*)
  
  integer :: ifldt
  real(DP) :: timee

  ifldt = ifield
!   if (ifldt.eq.0)       ifldt = 1
  if (ifldt == ifldmhd) ifldt = 1
!   write(6,*) ifldt,ifield,gsh_fld(ifldt),imesh,' ifldt'

  if (ifsync) call nekgsync()

#ifndef NOTIMER
  if (icalld == 0) then
      tdsmx=0.
      tdsmn=0.
  endif
  icalld=icalld+1
  etime1=dnekclock()
#endif


!               T         ~  ~T  T
!   Implement QQ   :=   J Q  Q  J


!                T
!   This is the J  part,  translating child data
!    call apply_Jt(u,nx,ny,nz,nel)



!               ~ ~T
!   This is the Q Q  part

  call gs_op(gsh_fld(ifldt),u,1,1,0)  ! 1 ==> +



!   This is the J  part,  interpolating parent solution onto child
!    call apply_J(u,nx,ny,nz,nel)


#ifndef NOTIMER
  timee=(dnekclock()-etime1)
  tdsum=tdsum+timee
  ndsum=ndsum + 1
  tdsmx=max(timee,tdsmx)
  tdsmn=min(timee,tdsmn)
#endif

  return
end subroutine dssum_dp
!-----------------------------------------------------------------------
!> \brief Direct stiffness sum
subroutine dssum_sp(u)
  use kinds, only : SP, DP
  use ctimer, only : ifsync, icalld, tdsmx, tdsmn, etime1, dnekclock
  use ctimer, only : tdsum, ndsum
  use input, only : ifldmhd
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  real(SP), intent(inout) :: u(*)
  
  integer :: ifldt
  real(DP) :: timee

  ifldt = ifield
  if (ifldt == ifldmhd) ifldt = 1

  if (ifsync) call nekgsync()

#ifndef NOTIMER
  if (icalld == 0) then
      tdsmx=0.
      tdsmn=0.
  endif
  icalld=icalld+1
  etime1=dnekclock()
#endif
  call gs_op(gsh_fld(ifldt),u,4,1,0)  ! 1 ==> +

#ifndef NOTIMER
  timee=(dnekclock()-etime1)
  tdsum=tdsum+timee
  ndsum=ndsum + 1
  tdsmx=max(timee,tdsmx)
  tdsmn=min(timee,tdsmn)
#endif

  return
end subroutine dssum_sp
!-----------------------------------------------------------------------
!> \brief Direct stiffness sum
subroutine dssum_irec_dp(u)
  use kinds, only : DP
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  real(DP), intent(inout) :: u(*)

#ifdef ASYNC
  call gs_op_irecv(gsh_fld(ifield), u, 1, 1, 0)
#endif

  return
end subroutine dssum_irec_dp


subroutine dssum_isend_dp(u)
  use size_m, only : lx1, ly1, lz1, lelv
  use kinds, only : DP
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  real(DP), intent(inout) :: u(*)
  integer :: i, n

#ifdef ASYNC
  n = lx1*ly1*lz1
  do i = 1, lelv
    call gs_op_isend_e(gsh_fld(ifield), u, 1, 1, 0, (i-1)*n, n)
 enddo
#endif

  return
end subroutine dssum_isend_dp

subroutine dssum_isend_e_dp(u,iel)
  use size_m, only : lx1, ly1, lz1, nelt
  use kinds, only : DP
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  real(DP), intent(inout) :: u(*)
  integer :: iel
  integer :: i, n

#ifdef ASYNC
  n = lx1*ly1*lz1
  call gs_op_isend_e(gsh_fld(ifield), u, 1, 1, 0, (iel-1)*n, n)
#endif

  return
end subroutine dssum_isend_e_dp


subroutine dssum_wait_dp(u)
  use kinds, only : DP
  use ctimer, only : ifsync
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  real(DP), intent(inout) :: u(*)

  if (ifsync) call nekgsync()
#ifdef ASYNC
  call gs_op_wait(gsh_fld(ifield), u, 1, 1, 0)
#else
  call gs_op(gsh_fld(ifield),u,1,1,0)  ! 1 ==> +
#endif

  return
end subroutine dssum_wait_dp

subroutine dssum_wait_e_dp(u,iel)
  use kinds, only : DP
  use size_m, only : lx1, ly1, lz1, lelv
  use ctimer, only : ifsync
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  real(DP), intent(inout) :: u(*)
  integer, intent(in) :: iel
  integer :: n

  if (ifsync) call nekgsync()
#ifdef ASYNC
  n = lx1*ly1*lz1
  call gs_op_wait_e(gsh_fld(ifield), u, 1, 1, 0, (iel-1)*n, n)
#else
  if (iel == 1) then
    call gs_op(gsh_fld(ifield),u,1,1,0)  ! 1 ==> +
  endif
#endif

  return
end subroutine dssum_wait_e_dp



!-----------------------------------------------------------------------
!> \brief generalization of dssum to other reducers.
!!
!!  o gs recognized operations:
!!          o "+" ==> addition.
!!          o "*" ==> multiplication.
!!          o "M" ==> maximum.
!!          o "m" ==> minimum.
!!          o "A" ==> (fabs(x)>fabs(y)) ? (x) : (y), ident=0.0.
!!          o "a" ==> (fabs(x)<fabs(y)) ? (x) : (y), ident=MAX_DBL
!!          o "e" ==> ((x)==0.0) ? (y) : (x),        ident=0.0.
!!          o note: a binary function pointer flavor exists.
!!
!!  o gs level:
!!          o level=0 ==> pure tree
!!          o level>=num_nodes-1 ==> pure pairwise
!!          o level = 1,...num_nodes-2 ==> mix tree/pairwise.
subroutine dsop(u,op)
  use kinds, only : DP
  use ctimer, only : ifsync
  use input, only : ifldmhd
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  real(DP) :: u(1)
  character(3) :: op
  integer :: ifldt

  ifldt = ifield
!   if (ifldt.eq.0)       ifldt = 1
  if (ifldt == ifldmhd) ifldt = 1

  if (ifsync) call nekgsync()

  if (op == '+  ') call gs_op(gsh_fld(ifldt),u,1,1,0)
  if (op == 'sum') call gs_op(gsh_fld(ifldt),u,1,1,0)
  if (op == 'SUM') call gs_op(gsh_fld(ifldt),u,1,1,0)

  if (op == '*  ') call gs_op(gsh_fld(ifldt),u,1,2,0)
  if (op == 'mul') call gs_op(gsh_fld(ifldt),u,1,2,0)
  if (op == 'MUL') call gs_op(gsh_fld(ifldt),u,1,2,0)

  if (op == 'm  ') call gs_op(gsh_fld(ifldt),u,1,3,0)
  if (op == 'min') call gs_op(gsh_fld(ifldt),u,1,3,0)
  if (op == 'mna') call gs_op(gsh_fld(ifldt),u,1,3,0)
  if (op == 'MIN') call gs_op(gsh_fld(ifldt),u,1,3,0)
  if (op == 'MNA') call gs_op(gsh_fld(ifldt),u,1,3,0)

  if (op == 'M  ') call gs_op(gsh_fld(ifldt),u,1,4,0)
  if (op == 'max') call gs_op(gsh_fld(ifldt),u,1,4,0)
  if (op == 'mxa') call gs_op(gsh_fld(ifldt),u,1,4,0)
  if (op == 'MAX') call gs_op(gsh_fld(ifldt),u,1,4,0)
  if (op == 'MXA') call gs_op(gsh_fld(ifldt),u,1,4,0)

  return
end subroutine dsop

!-----------------------------------------------------------------------
!> \brief Direct stiffness summation of the face data, for field U.
!!
!! Boundary condition data corresponds to component IFIELD of
!! the CBC array.
subroutine vec_dssum(u,v,w)
  use kinds, only : DP
  use size_m, only : ndim
  use ctimer, only : ifsync, icalld, tvdss, tgsum, nvdss, etime1, dnekclock
  use ctimer, only : tdsmx, tdsmn
  use input, only : ifldmhd
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  REAL(DP) :: U(1),V(1),W(1)
  integer :: ifldt
  real(DP) :: timee

  if(ifsync) call nekgsync()

#ifndef NOTIMER
  if (icalld == 0) tvdss=0.0d0
  if (icalld == 0) tgsum=0.0d0
  icalld=icalld+1
  nvdss=icalld
  etime1=dnekclock()
#endif

!============================================================================
!     execution phase
!============================================================================

  ifldt = ifield
!   if (ifldt.eq.0)       ifldt = 1
  if (ifldt == ifldmhd) ifldt = 1

  call gs_op_many(gsh_fld(ifldt),u,v,w,u,u,u,ndim,1,1,0)

#ifndef NOTIMER
  timee=(dnekclock()-etime1)
  tvdss=tvdss+timee
  tdsmx=max(timee,tdsmx)
  tdsmn=min(timee,tdsmn)
#endif

  return
end subroutine vec_dssum

!-----------------------------------------------------------------------
!> \brief Direct stiffness summation of the face data, for field U.
!! Boundary condition data corresponds to component IFIELD of
!! the CBC array.
subroutine vec_dsop(u,v,w,op)
  use kinds, only : DP
  use size_m, only : ndim
  use ctimer, only : ifsync
  use input, only : ifldmhd
  use parallel, only : gsh_fld
  use tstep, only : ifield
  implicit none

  real(DP) :: u(1),v(1),w(1)
  character(3) :: op
  integer :: ifldt

!============================================================================
!     execution phase
!============================================================================

  ifldt = ifield
!   if (ifldt.eq.0)       ifldt = 1
  if (ifldt == ifldmhd) ifldt = 1

!   write(6,*) 'opdsop: ',op,ifldt,ifield
  if(ifsync) call nekgsync()

  if (op == '+  ' .OR. op == 'sum' .OR. op == 'SUM') &
  call gs_op_many(gsh_fld(ifldt),u,v,w,u,u,u,ndim,1,1,0)


  if (op == '*  ' .OR. op == 'mul' .OR. op == 'MUL') &
  call gs_op_many(gsh_fld(ifldt),u,v,w,u,u,u,ndim,1,2,0)


  if (op == 'm  ' .OR. op == 'min' .OR. op == 'mna' &
   .OR. op == 'MIN' .OR. op == 'MNA') &
  call gs_op_many(gsh_fld(ifldt),u,v,w,u,u,u,ndim,1,3,0)


  if (op == 'M  ' .OR. op == 'max' .OR. op == 'mxa' &
   .OR. op == 'MAX' .OR. op == 'MXA') &
  call gs_op_many(gsh_fld(ifldt),u,v,w,u,u,u,ndim,1,4,0)


  return
end subroutine vec_dsop

!-----------------------------------------------------------------------
end module ds
